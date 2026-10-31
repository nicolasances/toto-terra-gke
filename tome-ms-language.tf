locals {
    tome_ms_language_namespace = "tome-ms-language"
    tome_ms_language_ksa = "tome-ms-language"

    # Workload Identity Federation for GKE: IAM is granted directly to the Kubernetes ServiceAccount, no GSA involved
    tome_ms_language_principal = format(
        "principal://iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s.svc.id.goog/subject/ns/%s/sa/%s",
        data.google_project.current.number,
        var.gcp_pid,
        local.tome_ms_language_namespace,
        local.tome_ms_language_ksa,
    )
}

# ---------------------------------------------------------------
# 1. Kubernetes Namespace & Service Account
# ---------------------------------------------------------------
resource "kubernetes_namespace_v1" "tome-ms-language-namespace" {
    metadata {
        name = local.tome_ms_language_namespace
    }
}
resource "kubernetes_service_account_v1" "tome-ms-language-ksa" {
    metadata {
        name = local.tome_ms_language_ksa
        namespace = kubernetes_namespace_v1.tome-ms-language-namespace.metadata[0].name
    }
}

# ---------------------------------------------------------------
# 2. IAM Roles (granted to the Kubernetes Service Account principal)
# ---------------------------------------------------------------
resource "google_project_iam_member" "tome-ms-language-role-secretmanagedaccessor" {
    project = var.gcp_pid
    role = "roles/secretmanager.secretAccessor"
    member = local.tome_ms_language_principal
}

# ---------------------------------------------------------------
# 3. Environment variables (to be used with envFrom in the Deployment)
# ---------------------------------------------------------------
resource "kubernetes_config_map_v1" "tome-ms-language-config" {
    metadata {
        name = "tome-ms-language-config"
        namespace = kubernetes_namespace_v1.tome-ms-language-namespace.metadata[0].name
    }
    data = {
        HYPERSCALER = "gcp"
        GCP_PID = var.gcp_pid
    }
}

# ---------------------------------------------------------------
# 4. Google Secret Manager (Secrets)
# ---------------------------------------------------------------
variable "tome_ms_language_mongo_user" {
    description = "Mongo User for tome-ms-language"
    type = string
    sensitive = true
}
variable "tome_ms_language_mongo_pswd" {
    description = "Mongo Password for tome-ms-language"
    type = string
    sensitive = true
}
resource "google_secret_manager_secret" "tome-ms-language-mongo-user" {
    secret_id = "tome-ms-language-mongo-user"
    replication {
        auto { }
    }
    depends_on = [google_project_service.secretmanager-api]
}
resource "google_secret_manager_secret_version" "tome-ms-language-mongo-user-version" {
    secret = google_secret_manager_secret.tome-ms-language-mongo-user.id
    secret_data = var.tome_ms_language_mongo_user
}
resource "google_secret_manager_secret" "tome-ms-language-mongo-pswd" {
    secret_id = "tome-ms-language-mongo-pswd"
    replication {
        auto { }
    }
    depends_on = [google_project_service.secretmanager-api]
}
resource "google_secret_manager_secret_version" "tome-ms-language-mongo-pswd-version" {
    secret = google_secret_manager_secret.tome-ms-language-mongo-pswd.id
    secret_data = var.tome_ms_language_mongo_pswd
}
