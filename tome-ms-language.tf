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
