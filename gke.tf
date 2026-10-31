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
