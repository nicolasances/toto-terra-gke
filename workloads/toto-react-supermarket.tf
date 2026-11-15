# ---------------------------------------------------------------
# toto-suppie (Next.js web app, image toto-react-supermarket).
# Unlike the microservices, it is served on its own hostname (suppie[.dev].dr.<domain>) on "/".
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# 1. Kubernetes Service Account (one per environment namespace)
# ---------------------------------------------------------------
# Access to GCP (Speech-to-Text, Text-to-Speech) is granted to this KSA in toto-terra, through
# Workload Identity Federation for GKE, with the principal:
# principal://iam.googleapis.com/projects/<gke project number>/locations/global/workloadIdentityPools/<gke project id>.svc.id.goog/subject/ns/<env>/sa/toto-react-supermarket
resource "kubernetes_service_account_v1" "toto-react-supermarket-ksa" {
    for_each = local.environments

    metadata {
        name = "toto-react-supermarket"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
}

# ---------------------------------------------------------------
# 2. Environment variables (to be used with envFrom in the Deployment)
# ---------------------------------------------------------------
# The NEXT_PUBLIC_* variables (API endpoints, Google client ID) are baked into the image at
# build time (toto-suppie GitHub workflows): they are NOT set here.
resource "kubernetes_config_map_v1" "toto-react-supermarket-config" {
    for_each = local.environments

    metadata {
        name = "toto-react-supermarket-config"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    data = {
        # The STT/TTS API routes call Google APIs with the env project (as on Cloud Run).
        # The federated principal has no home project, so the quota project must be explicit.
        GOOGLE_CLOUD_PROJECT = each.value
        GOOGLE_CLOUD_QUOTA_PROJECT = each.value
    }
}

# ---------------------------------------------------------------
# 3. Deployment
# ---------------------------------------------------------------
variable "toto_react_supermarket_image_tag" {
    description = "Image tag (package.json version) of toto-react-supermarket (toto-suppie) to deploy, per environment (keys: dev, prod)"
    type = map(string)
}
resource "kubernetes_deployment_v1" "toto-react-supermarket-deployment" {
    for_each = local.environments

    metadata {
        name = "toto-react-supermarket"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        labels = {
            app = "toto-react-supermarket"
        }
    }
    spec {
        replicas = 1
        selector {
            match_labels = {
                app = "toto-react-supermarket"
            }
        }
        template {
            metadata {
                labels = {
                    app = "toto-react-supermarket"
                }
            }
            spec {
                service_account_name = kubernetes_service_account_v1.toto-react-supermarket-ksa[each.key].metadata[0].name
                container {
                    name = "toto-react-supermarket"
                    # The image is pulled from the environment's own Artifact Registry (managed by toto-terra)
                    image = format("europe-west1-docker.pkg.dev/%s/toto-react-supermarket/toto-react-supermarket:%s", each.value, var.toto_react_supermarket_image_tag[each.key])
                    # Next.js (npm start) listens on 3000
                    port {
                        name = "http"
                        container_port = 3000
                    }
                    env_from {
                        config_map_ref {
                            name = kubernetes_config_map_v1.toto-react-supermarket-config[each.key].metadata[0].name
                        }
                    }
                    readiness_probe {
                        http_get {
                            path = "/api/health"
                            port = "http"
                        }
                        initial_delay_seconds = 5
                        period_seconds = 10
                        failure_threshold = 3
                    }
                    liveness_probe {
                        http_get {
                            path = "/api/health"
                            port = "http"
                        }
                        initial_delay_seconds = 20
                        period_seconds = 20
                        failure_threshold = 3
                    }
                    # Next.js needs more memory than a totoms service. Starting point: tune after watching real usage
                    resources {
                        requests = {
                            cpu = "250m"
                            memory = "512Mi"
                        }
                        limits = {
                            cpu = "1"
                            memory = "1Gi"
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
resource "kubernetes_service_v1" "toto-react-supermarket-service" {
    for_each = local.environments

    metadata {
        name = "toto-react-supermarket"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    spec {
        type = "ClusterIP"
        selector = {
            app = "toto-react-supermarket"
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
#    https://<suppie hostname>/... -> this service
# ---------------------------------------------------------------
resource "kubernetes_manifest" "toto-react-supermarket-route" {
    for_each = local.environments

    manifest = {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind = "HTTPRoute"
        metadata = {
            name = "toto-react-supermarket"
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
            # Own hostname (created in cluster/edge.tf), the whole app is served on "/"
            hostnames = [data.terraform_remote_state.cluster.outputs.suppie_hostnames[each.key]]
            rules = [
                {
                    matches = [
                        {
                            path = {
                                type = "PathPrefix"
                                value = "/"
                            }
                        },
                    ]
                    backendRefs = [
                        {
                            name = kubernetes_service_v1.toto-react-supermarket-service[each.key].metadata[0].name
                            port = 80
                        },
                    ]
                },
            ]
        }
    }
}

# The load balancer health-checks "/" by default: point it to the app's health endpoint
resource "kubernetes_manifest" "toto-react-supermarket-healthcheck" {
    for_each = local.environments

    manifest = {
        apiVersion = "networking.gke.io/v1"
        kind = "HealthCheckPolicy"
        metadata = {
            name = "toto-react-supermarket"
            namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        }
        spec = {
            default = {
                config = {
                    type = "HTTP"
                    httpHealthCheck = {
                        requestPath = "/api/health"
                    }
                }
            }
            targetRef = {
                group = ""
                kind = "Service"
                name = kubernetes_service_v1.toto-react-supermarket-service[each.key].metadata[0].name
            }
        }
    }
}
