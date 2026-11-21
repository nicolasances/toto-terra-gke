# ---------------------------------------------------------------
# toto-reactjs-expenses (Next.js web app, Toto Expenses).
# Unlike the microservices, it is served on its own hostname (money[.dev].dr.<domain>) on "/".
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# 1. Kubernetes Service Account (one per environment namespace)
# ---------------------------------------------------------------
# No GCP access is granted to this KSA for now.
resource "kubernetes_service_account_v1" "toto-reactjs-expenses-ksa" {
    for_each = local.environments

    metadata {
        name = "toto-reactjs-expenses"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
}

# ---------------------------------------------------------------
# 2. Deployment
# ---------------------------------------------------------------
# The NEXT_PUBLIC_* variables (API endpoints, Google client ID) are baked into the image at
# build time (toto-reactjs-expenses GitHub workflows): no ConfigMap / runtime env is needed.
variable "toto_reactjs_expenses_image_tag" {
    description = "Image tag (package.json version) of toto-reactjs-expenses to deploy, per environment (keys: dev, prod). Only used when the Deployment is created: after that CI owns the image and changing this has no effect"
    type = map(string)
}
resource "kubernetes_deployment_v1" "toto-reactjs-expenses-deployment" {
    for_each = local.environments

    metadata {
        name = "toto-reactjs-expenses"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
        labels = {
            app = "toto-reactjs-expenses"
        }
    }
    spec {
        replicas = 1
        selector {
            match_labels = {
                app = "toto-reactjs-expenses"
            }
        }
        template {
            metadata {
                labels = {
                    app = "toto-reactjs-expenses"
                }
            }
            spec {
                service_account_name = kubernetes_service_account_v1.toto-reactjs-expenses-ksa[each.key].metadata[0].name
                container {
                    name = "toto-reactjs-expenses"
                    # The image is pulled from the environment's own Artifact Registry (managed by toto-terra)
                    image = format("europe-west1-docker.pkg.dev/%s/toto-reactjs-expenses/toto-reactjs-expenses:%s", each.value, var.toto_reactjs_expenses_image_tag[each.key])
                    # The Next.js standalone server runs with PORT=8080
                    port {
                        name = "http"
                        container_port = 8080
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
            # CI (GitHub Actions in the service repo) owns the image after creation:
            # it runs `kubectl set image`. Terraform only sets it when it creates the Deployment.
            spec[0].template[0].spec[0].container[0].image,
        ]
    }
}

# ---------------------------------------------------------------
# 3. Service (internal to the cluster)
# ---------------------------------------------------------------
resource "kubernetes_service_v1" "toto-reactjs-expenses-service" {
    for_each = local.environments

    metadata {
        name = "toto-reactjs-expenses"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    spec {
        type = "ClusterIP"
        selector = {
            app = "toto-reactjs-expenses"
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
# 4. Public exposure through the shared Gateway
#    https://<money hostname>/... -> this service
# ---------------------------------------------------------------
resource "kubernetes_manifest" "toto-reactjs-expenses-route" {
    for_each = local.environments

    manifest = {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind = "HTTPRoute"
        metadata = {
            name = "toto-reactjs-expenses"
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
            hostnames = [data.terraform_remote_state.cluster.outputs.money_hostnames[each.key]]
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
                            name = kubernetes_service_v1.toto-reactjs-expenses-service[each.key].metadata[0].name
                            port = 80
                        },
                    ]
                },
            ]
        }
    }
}

# The load balancer health-checks "/" by default: point it to the app's health endpoint
resource "kubernetes_manifest" "toto-reactjs-expenses-healthcheck" {
    for_each = local.environments

    manifest = {
        apiVersion = "networking.gke.io/v1"
        kind = "HealthCheckPolicy"
        metadata = {
            name = "toto-reactjs-expenses"
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
                name = kubernetes_service_v1.toto-reactjs-expenses-service[each.key].metadata[0].name
            }
        }
    }
}
