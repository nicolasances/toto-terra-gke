# ---------------------------------------------------------------
# 1. Kubernetes Service Account (one per environment namespace)
# ---------------------------------------------------------------
# Access to GCP (e.g. Secret Manager) is granted to this KSA in toto-terra, through
# Workload Identity Federation for GKE, with the principal:
# principal://iam.googleapis.com/projects/<gke project number>/locations/global/workloadIdentityPools/<gke project id>.svc.id.goog/subject/ns/<env>/sa/toto-ms-auth
resource "kubernetes_service_account_v1" "toto-ms-auth-ksa" {
    for_each = local.environments

    metadata {
        name = "toto-ms-auth"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
}

# ---------------------------------------------------------------
# 2. Environment variables (to be used with envFrom in the Deployment)
# ---------------------------------------------------------------
resource "kubernetes_config_map_v1" "toto-ms-auth-config" {
    for_each = local.environments

    metadata {
        name = "toto-ms-auth-config"
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
variable "toto_ms_auth_image_tag" {
    description = "Image tag (package.json version) of toto-ms-auth to deploy, per environment (keys: dev, prod)"
    type = map(string)
}
resource "kubernetes_deployment_v1" "toto-ms-auth-deployment" {
    for_each = local.environments

    metadata {
        name = "toto-ms-auth"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        labels = {
            app = "toto-ms-auth"
        }
    }
    spec {
        replicas = 1
        selector {
            match_labels = {
                app = "toto-ms-auth"
            }
        }
        template {
            metadata {
                labels = {
                    app = "toto-ms-auth"
                }
            }
            spec {
                service_account_name = kubernetes_service_account_v1.toto-ms-auth-ksa[each.key].metadata[0].name
                container {
                    name = "toto-ms-auth"
                    # The image is pulled from the environment's own Artifact Registry (managed by toto-terra)
                    image = format("europe-west1-docker.pkg.dev/%s/toto-ms-auth/toto-ms-auth:%s", each.value, var.toto_ms_auth_image_tag[each.key])
                    port {
                        name = "http"
                        container_port = 8080
                    }
                    env_from {
                        config_map_ref {
                            name = kubernetes_config_map_v1.toto-ms-auth-config[each.key].metadata[0].name
                        }
                    }
                    # /health is registered by totoms, outside of the /auth base path
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

    # Autopilot mutates the Deployment at admission (warden): it adds annotations, default
    # ephemeral-storage, security contexts and an arch toleration. Don't try to revert them.
    lifecycle {
        ignore_changes = [
            metadata[0].annotations["autopilot.gke.io/resource-adjustment"],
            metadata[0].annotations["autopilot.gke.io/warden-version"],
            spec[0].template[0].spec[0].container[0].resources[0].limits["ephemeral-storage"],
            spec[0].template[0].spec[0].container[0].resources[0].requests["ephemeral-storage"],
            spec[0].template[0].spec[0].container[0].security_context,
            spec[0].template[0].spec[0].security_context,
            spec[0].template[0].spec[0].toleration,
        ]
    }
}

# ---------------------------------------------------------------
# 4. Service (internal to the cluster)
# ---------------------------------------------------------------
resource "kubernetes_service_v1" "toto-ms-auth-service" {
    for_each = local.environments

    metadata {
        name = "toto-ms-auth"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    spec {
        type = "ClusterIP"
        selector = {
            app = "toto-ms-auth"
        }
        port {
            name = "http"
            port = 80
            target_port = "http"
        }
    }

    # The GKE NEG controller (used by the Gateway) annotates the Service. Don't try to revert it.
    lifecycle {
        ignore_changes = [
            metadata[0].annotations["cloud.google.com/neg"],
            metadata[0].annotations["cloud.google.com/neg-status"],
        ]
    }
}

# ---------------------------------------------------------------
# 5. Public exposure through the shared Gateway
#    https://<environment hostname>/auth/... -> this service
# ---------------------------------------------------------------
resource "kubernetes_manifest" "toto-ms-auth-route" {
    for_each = local.environments

    manifest = {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind = "HTTPRoute"
        metadata = {
            name = "toto-ms-auth"
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
                                value = "/auth"
                            }
                        },
                    ]
                    backendRefs = [
                        {
                            name = kubernetes_service_v1.toto-ms-auth-service[each.key].metadata[0].name
                            port = 80
                        },
                    ]
                },
            ]
        }
    }
}

# The load balancer health-checks "/" by default, which the service does not serve: point it to /health
resource "kubernetes_manifest" "toto-ms-auth-healthcheck" {
    for_each = local.environments

    manifest = {
        apiVersion = "networking.gke.io/v1"
        kind = "HealthCheckPolicy"
        metadata = {
            name = "toto-ms-auth"
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
                name = kubernetes_service_v1.toto-ms-auth-service[each.key].metadata[0].name
            }
        }
    }
}
