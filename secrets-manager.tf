# ---------------------------------------------------------------
# Shared secrets read by every totoms microservice at startup
# (see TotoControllerConfig.load() in toto-microservice-sdk)
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# 1. Variables for Secret Manager
# ---------------------------------------------------------------
variable "mongo_host" {
    description = "Mongo host shared by the microservices"
    type = string
    sensitive = true
}
variable "jwt_signing_key" {
    description = "Key used to sign custom JWT tokens"
    type = string
    sensitive = true
}
variable "target_audience" {
    description = "Target Audience to use in JWT flows"
    type = string
    sensitive = true
}
variable "toto_registry_endpoint" {
    description = "Endpoint of toto-ms-registry"
    type = string
}

# ---------------------------------------------------------------
# 2. Generic Secrets to be stored in Secrets Manager
# ---------------------------------------------------------------
resource "google_secret_manager_secret" "secret_mongo_host" {
    secret_id = "mongo-host"
    replication {
        auto { }
    }
    depends_on = [google_project_service.secretmanager-api]
}
resource "google_secret_manager_secret_version" "secret_mongo_host_version" {
    secret = google_secret_manager_secret.secret_mongo_host.id
    secret_data = var.mongo_host
}
resource "google_secret_manager_secret" "secret_jwt_signing_key" {
    secret_id = "jwt-signing-key"
    replication {
        auto { }
    }
    depends_on = [google_project_service.secretmanager-api]
}
resource "google_secret_manager_secret_version" "secret_version_jwt_signing_key" {
    secret = google_secret_manager_secret.secret_jwt_signing_key.id
    secret_data = var.jwt_signing_key
}
resource "google_secret_manager_secret" "secret_target_audience" {
    secret_id = "toto-expected-audience"
    replication {
        auto { }
    }
    depends_on = [google_project_service.secretmanager-api]
}
resource "google_secret_manager_secret_version" "secret_version_target_audience" {
    secret = google_secret_manager_secret.secret_target_audience.id
    secret_data = var.target_audience
}
resource "google_secret_manager_secret" "secret_toto_registry_endpoint" {
    secret_id = "toto-registry-endpoint"
    replication {
        auto { }
    }
    depends_on = [google_project_service.secretmanager-api]
}
resource "google_secret_manager_secret_version" "secret_version_toto_registry_endpoint" {
    secret = google_secret_manager_secret.secret_toto_registry_endpoint.id
    secret_data = var.toto_registry_endpoint
}
