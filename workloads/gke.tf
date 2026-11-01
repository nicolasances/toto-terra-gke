# ---------------------------------------------------------------
# Environments hosted on the cluster, one namespace each.
# Each environment maps to the GCP project holding its secrets and
# resources (managed by toto-terra).
# ---------------------------------------------------------------
locals {
    environments = {
        dev = "totoexperiments"
        prod = "totolive"
    }
}

resource "kubernetes_namespace_v1" "env-namespace" {
    for_each = local.environments

    metadata {
        name = each.key
    }
}

# ---------------------------------------------------------------
# Public Gateway: ONE global external HTTPS load balancer shared by all
# services and environments. Each service exposes itself by adding an
# HTTPRoute in its environment namespace, attached to the "https" listener.
# ---------------------------------------------------------------
locals {
    gateway_name = "public-gateway"
}

resource "kubernetes_namespace_v1" "gateway-namespace" {
    metadata {
        name = "gateway"
    }
}

resource "kubernetes_manifest" "gateway" {
    manifest = {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind = "Gateway"
        metadata = {
            name = local.gateway_name
            namespace = kubernetes_namespace_v1.gateway-namespace.metadata[0].name
            annotations = {
                # Google-managed certificate created in cluster/
                "networking.gke.io/certmap" = data.terraform_remote_state.cluster.outputs.gateway_certmap_name
            }
        }
        spec = {
            gatewayClassName = "gke-l7-global-external-managed"
            addresses = [
                {
                    type = "NamedAddress"
                    value = data.terraform_remote_state.cluster.outputs.gateway_ip_name
                },
            ]
            listeners = [
                {
                    # Routes can only attach from the environment namespaces
                    name = "https"
                    protocol = "HTTPS"
                    port = 443
                    allowedRoutes = {
                        namespaces = {
                            from = "Selector"
                            selector = {
                                matchExpressions = [
                                    {
                                        key = "kubernetes.io/metadata.name"
                                        operator = "In"
                                        values = keys(local.environments)
                                    },
                                ]
                            }
                        }
                    }
                },
                {
                    # Only used to redirect to HTTPS (see below)
                    name = "http"
                    protocol = "HTTP"
                    port = 80
                    allowedRoutes = {
                        namespaces = {
                            from = "Same"
                        }
                    }
                },
            ]
        }
    }
}

# Redirects every HTTP request to HTTPS
resource "kubernetes_manifest" "gateway-http-to-https" {
    manifest = {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind = "HTTPRoute"
        metadata = {
            name = "http-to-https"
            namespace = kubernetes_namespace_v1.gateway-namespace.metadata[0].name
        }
        spec = {
            parentRefs = [
                {
                    name = local.gateway_name
                    sectionName = "http"
                },
            ]
            rules = [
                {
                    filters = [
                        {
                            type = "RequestRedirect"
                            requestRedirect = {
                                scheme = "https"
                                statusCode = 301
                            }
                        },
                    ]
                },
            ]
        }
    }
}
