# ---------------------------------------------------------------
# agent-coder: takes one GitHub issue, opens one PR, exits.
# Runs as a KEDA ScaledJob driven by a Pub/Sub backlog: each pod pulls ONE message,
# runs the task and exits. Needs KEDA, installed by platform/ (apply that first).
#
# Separate namespaces from the services (agents-dev / agents-prod), mapped to the same
# toto projects as dev / prod (which hold the secrets, the agents-data bucket and the image).
# Pub/Sub lives in the GKE project, not in the toto projects.
# ---------------------------------------------------------------
locals {
    agent_environments = {
        for env, project in local.environments : env => {
            namespace = format("agents-%s", env)
            toto_project = project
        }
    }
}

variable "agent_coder_image_tag" {
    description = "Image tag of agent-coder to deploy, per environment (keys: dev, prod). Only used when the ScaledJob is created: after that CI owns the image and changing this has no effect"
    type = map(string)
}
variable "agent_coder_max_replicas" {
    description = "Maximum number of agent-coder jobs running at once, per environment (keys: dev, prod)"
    type = map(number)
    default = {
        dev = 10
        prod = 10
    }
}
variable "agent_coder_cpu" {
    description = "CPU of an agent-coder pod (request = limit)"
    type = string
    default = "1"
}
variable "agent_coder_memory" {
    description = "Memory of an agent-coder pod (request = limit)"
    type = string
    default = "2Gi"
}
variable "agent_coder_ephemeral_storage" {
    description = "Ephemeral storage of an agent-coder pod (request = limit): holds the cloned repo"
    type = string
    default = "5Gi"
}

# ---------------------------------------------------------------
# 1. Namespaces and Kubernetes Service Account
# ---------------------------------------------------------------
# Workload Identity (direct federation, no Google service account): the grants in the toto
# projects (secrets, bucket) are made in toto-terra for the principal
# ns/agents-<env>/sa/agent-coder.
resource "kubernetes_namespace_v1" "agents-namespace" {
    for_each = local.agent_environments

    metadata {
        name = each.value.namespace
    }
}

resource "kubernetes_service_account_v1" "agent-coder-ksa" {
    for_each = local.agent_environments

    metadata {
        name = "agent-coder"
        namespace = kubernetes_namespace_v1.agents-namespace[each.key].metadata[0].name
    }
}

# ---------------------------------------------------------------
# 2. Pub/Sub (in the GKE project)
#    Message contract: {"taskId": "<id>"}. task.json stays in
#    gs://<toto project>-agents-data/coder/<taskId>/task.json
# ---------------------------------------------------------------
resource "google_pubsub_topic" "agent-coder-tasks" {
    for_each = local.agent_environments

    name = format("agent-coder-tasks-%s", each.key)
}

resource "google_pubsub_topic" "agent-coder-dlq" {
    for_each = local.agent_environments

    name = format("agent-coder-tasks-%s-dlq", each.key)
}

# Keeps the dead-lettered messages (7 days, the default) so they can be inspected or replayed
resource "google_pubsub_subscription" "agent-coder-dlq-sub" {
    for_each = local.agent_environments

    name = format("agent-coder-tasks-%s-dlq-sub", each.key)
    topic = google_pubsub_topic.agent-coder-dlq[each.key].id
}

resource "google_pubsub_subscription" "agent-coder-sub" {
    for_each = local.agent_environments

    name = format("agent-coder-tasks-%s-sub", each.key)
    topic = google_pubsub_topic.agent-coder-tasks[each.key].id

    enable_exactly_once_delivery = true
    # The runner extends the lease every ~5 minutes
    ack_deadline_seconds = 600
    message_retention_duration = "604800s"

    dead_letter_policy {
        dead_letter_topic = google_pubsub_topic.agent-coder-dlq[each.key].id
        max_delivery_attempts = 3
    }
}

# The Pub/Sub IAM grants are made BY HAND, not here: the Terraform VM can't read or set IAM
# policies on topics and subscriptions (403 pubsub.topics.getIamPolicy). See "Agents" in
# docs/operations.md. Per environment:
#   - Pub/Sub service agent: publisher on the DLQ topic, subscriber on the source subscription
#   - principal ns/agents-<env>/sa/agent-coder: subscriber on its own subscription only

# ---------------------------------------------------------------
# 3. KEDA: authentication and ScaledJob
# ---------------------------------------------------------------
# GCP pod identity: KEDA's operator reads the backlog from Cloud Monitoring with its own
# Workload Identity (roles/monitoring.viewer, granted in platform/)
resource "kubernetes_manifest" "agent-coder-trigger-auth" {
    for_each = local.agent_environments

    manifest = {
        apiVersion = "keda.sh/v1alpha1"
        kind = "TriggerAuthentication"
        metadata = {
            name = "agent-coder-gcp"
            namespace = kubernetes_namespace_v1.agents-namespace[each.key].metadata[0].name
        }
        spec = {
            podIdentity = {
                provider = "gcp"
            }
        }
    }
}

resource "kubernetes_manifest" "agent-coder-scaledjob" {
    for_each = local.agent_environments

    manifest = {
        apiVersion = "keda.sh/v1alpha1"
        kind = "ScaledJob"
        metadata = {
            name = "agent-coder"
            namespace = kubernetes_namespace_v1.agents-namespace[each.key].metadata[0].name
        }
        spec = {
            pollingInterval = 30
            maxReplicaCount = var.agent_coder_max_replicas[each.key]
            successfulJobsHistoryLimit = 3
            failedJobsHistoryLimit = 3
            # "default" subtracts the running jobs from the backlog. The Pub/Sub backlog counts
            # leased-but-unacked messages too, so jobs already working on a message don't spawn duplicates.
            scalingStrategy = {
                strategy = "default"
            }
            triggers = [
                {
                    type = "gcp-pubsub"
                    authenticationRef = {
                        name = "agent-coder-gcp"
                    }
                    metadata = {
                        projectID = var.gcp_pid
                        subscriptionName = google_pubsub_subscription.agent-coder-sub[each.key].name
                        mode = "SubscriptionSize"
                        # One job per message
                        value = "1"
                    }
                },
            ]
            jobTargetRef = {
                # Retries come from Pub/Sub redelivery (and the DLQ), not from Kubernetes
                backoffLimit = 0
                # Hard backstop (3h15m), above the runner's own 3h timeout
                activeDeadlineSeconds = 11700
                template = {
                    metadata = {
                        annotations = {
                            "cluster-autoscaler.kubernetes.io/safe-to-evict" = "false"
                        }
                    }
                    spec = {
                        serviceAccountName = kubernetes_service_account_v1.agent-coder-ksa[each.key].metadata[0].name
                        restartPolicy = "Never"
                        # Time for the runner to nack its message on SIGTERM
                        terminationGracePeriodSeconds = 60
                        containers = [
                            {
                                name = "agent-coder"
                                image = format("europe-west1-docker.pkg.dev/%s/agent-coder/agent-coder:%s", each.value.toto_project, var.agent_coder_image_tag[each.key])
                                env = [
                                    { name = "GCP_PID", value = each.value.toto_project },
                                    { name = "PUBSUB_PROJECT_ID", value = var.gcp_pid },
                                    { name = "PUBSUB_SUBSCRIPTION", value = google_pubsub_subscription.agent-coder-sub[each.key].name },
                                    { name = "TASK_TIMEOUT_SECONDS", value = "10800" },
                                ]
                                resources = {
                                    requests = {
                                        cpu = var.agent_coder_cpu
                                        memory = var.agent_coder_memory
                                        "ephemeral-storage" = var.agent_coder_ephemeral_storage
                                    }
                                    limits = {
                                        cpu = var.agent_coder_cpu
                                        memory = var.agent_coder_memory
                                        "ephemeral-storage" = var.agent_coder_ephemeral_storage
                                    }
                                }
                            },
                        ]
                    }
                }
            }
        }
    }

    # CI (GitHub Actions in agent-coder) owns the image after creation: it patches the ScaledJob.
    # Terraform only sets it when it creates the ScaledJob.
    lifecycle {
        ignore_changes = [
            manifest.spec.jobTargetRef.template.spec.containers[0].image,
        ]
    }

    depends_on = [kubernetes_manifest.agent-coder-trigger-auth]
}

# ---------------------------------------------------------------
# 4. CI deployer: lets toto-cicd@<env project> roll out a new image
#    (patch of the ScaledJob) in its own agents namespace only
# ---------------------------------------------------------------
resource "kubernetes_role_v1" "agents-ci-deployer" {
    for_each = local.agent_environments

    metadata {
        name = "ci-deployer"
        namespace = kubernetes_namespace_v1.agents-namespace[each.key].metadata[0].name
    }

    rule {
        api_groups = ["keda.sh"]
        resources = ["scaledjobs"]
        verbs = ["get", "patch"]
    }

    # Read-only, for debugging from CI
    rule {
        api_groups = ["batch"]
        resources = ["jobs"]
        verbs = ["get", "list", "watch"]
    }
    rule {
        api_groups = [""]
        resources = ["pods"]
        verbs = ["get", "list", "watch"]
    }
}

resource "kubernetes_role_binding_v1" "agents-ci-deployer" {
    for_each = local.agent_environments

    metadata {
        name = "ci-deployer"
        namespace = kubernetes_namespace_v1.agents-namespace[each.key].metadata[0].name
    }
    role_ref {
        api_group = "rbac.authorization.k8s.io"
        kind = "Role"
        name = kubernetes_role_v1.agents-ci-deployer[each.key].metadata[0].name
    }
    subject {
        api_group = "rbac.authorization.k8s.io"
        kind = "User"
        name = format("toto-cicd@%s.iam.gserviceaccount.com", each.value.toto_project)
    }
}
