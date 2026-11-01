# ---------------------------------------------------------------
# 1. Kubernetes Service Account (one per environment namespace)
# ---------------------------------------------------------------
# Access to GCP (e.g. Secret Manager) is granted to this KSA in toto-terra, through
# Workload Identity Federation for GKE, with the principal:
# principal://iam.googleapis.com/projects/<gke project number>/locations/global/workloadIdentityPools/<gke project id>.svc.id.goog/subject/ns/<env>/sa/tome-ms-language
resource "kubernetes_service_account_v1" "tome-ms-language-ksa" {
    for_each = local.environments

    metadata {
        name = "tome-ms-language"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
}

# ---------------------------------------------------------------
# 2. Environment variables (to be used with envFrom in the Deployment)
# ---------------------------------------------------------------
resource "kubernetes_config_map_v1" "tome-ms-language-config" {
    for_each = local.environments

    metadata {
        name = "tome-ms-language-config"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    data = {
        HYPERSCALER = "gcp"
        GCP_PID = each.value
    }
}

# ---------------------------------------------------------------
# 3. Deployment
# ---------------------------------------------------------------
variable "tome_ms_language_image_tag" {
    description = "Image tag (package.json version) of tome-ms-language to deploy, per environment (keys: dev, prod)"
    type = map(string)
}
resource "kubernetes_deployment_v1" "tome-ms-language-deployment" {
    for_each = local.environments

    metadata {
        name = "tome-ms-language"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        labels = {
            app = "tome-ms-language"
        }
    }
    spec {
        replicas = 1
        selector {
            match_labels = {
                app = "tome-ms-language"
            }
        }
        template {
            metadata {
                labels = {
                    app = "tome-ms-language"
                }
            }
            spec {
                service_account_name = kubernetes_service_account_v1.tome-ms-language-ksa[each.key].metadata[0].name
                container {
                    name = "tome-ms-language"
                    # The image is pulled from the environment's own Artifact Registry (managed by toto-terra)
                    image = format("europe-west1-docker.pkg.dev/%s/tome-ms-language/tome-ms-language:%s", each.value, var.tome_ms_language_image_tag[each.key])
                    port {
                        name = "http"
                        container_port = 8080
                    }
                    env_from {
                        config_map_ref {
                            name = kubernetes_config_map_v1.tome-ms-language-config[each.key].metadata[0].name
                        }
                    }
                    # /health is registered by totoms, outside of the /tomelang base path
                    readiness_probe {
                        http_get {
                            path = "/health"
                            port = "http"
                        }
                        initial_delay_seconds = 5
                        period_seconds = 10
                        failure_threshold = 3
                    }
                    liveness_probe {
                        http_get {
                            path = "/health"
                            port = "http"
                        }
                        initial_delay_seconds = 15
                        period_seconds = 20
                        failure_threshold = 3
                    }
                    resources {
                        requests = {
                            cpu = "100m"
                            memory = "192Mi"
                        }
                        limits = {
                            cpu = "500m"
                            memory = "384Mi"
                        }
                    }
                }
            }
        }
    }
}

# ---------------------------------------------------------------
# 4. Service (internal to the cluster)
# ---------------------------------------------------------------
resource "kubernetes_service_v1" "tome-ms-language-service" {
    for_each = local.environments

    metadata {
        name = "tome-ms-language"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    spec {
        type = "ClusterIP"
        selector = {
            app = "tome-ms-language"
        }
        port {
            name = "http"
            port = 80
            target_port = "http"
        }
    }
}

# ---------------------------------------------------------------
# 5. Public exposure through the shared Gateway
#    https://<environment hostname>/tomelang/... -> this service
# ---------------------------------------------------------------
resource "kubernetes_manifest" "tome-ms-language-route" {
    for_each = local.environments

    manifest = {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind = "HTTPRoute"
        metadata = {
            name = "tome-ms-language"
            namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        }
        spec = {
            parentRefs = [
                {
                    name = local.gateway_name
                    namespace = kubernetes_namespace_v1.gateway-namespace.metadata[0].name
                    sectionName = "https"
                },
            ]
            hostnames = [data.terraform_remote_state.cluster.outputs.env_hostnames[each.key]]
            rules = [
                {
                    matches = [
                        {
                            path = {
                                type = "PathPrefix"
                                value = "/tomelang"
                            }
                        },
                    ]
                    backendRefs = [
                        {
                            name = kubernetes_service_v1.tome-ms-language-service[each.key].metadata[0].name
                            port = 80
                        },
                    ]
                },
            ]
        }
    }
}

# The load balancer health-checks "/" by default, which the service does not serve: point it to /health
resource "kubernetes_manifest" "tome-ms-language-healthcheck" {
    for_each = local.environments

    manifest = {
        apiVersion = "networking.gke.io/v1"
        kind = "HealthCheckPolicy"
        metadata = {
            name = "tome-ms-language"
            namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        }
        spec = {
            default = {
                config = {
                    type = "HTTP"
                    httpHealthCheck = {
                        requestPath = "/health"
                    }
                }
            }
            targetRef = {
                group = ""
                kind = "Service"
                name = kubernetes_service_v1.tome-ms-language-service[each.key].metadata[0].name
            }
        }
    }
}
