terraform {
    required_providers {
        google = {
            source = "hashicorp/google"
            version = "7.15.0"
        }
        kubernetes = {
            source = "hashicorp/kubernetes"
            version = "2.38.0"
        }
    }
    backend "gcs" {
        bucket = "toto-terra-gke-dr"
        prefix = "terraform/state"
    }
}

# Credentials come from the environment (Application Default Credentials):
# on the Terraform VM, that is the VM's attached service account
provider "google" {
    project = var.gcp_pid
    region = var.gcp_region
    zone = var.gcp_zone

}

# ---------------------------------------------------------------
# Kubernetes provider, authenticated against the existing GKE cluster
# with the same identity Terraform uses for the google provider
# ---------------------------------------------------------------
data "google_client_config" "current" {}

data "google_container_cluster" "gke-cluster" {
    name = var.gke_cluster_name
    location = var.gke_cluster_location
}

provider "kubernetes" {
    host = format("https://%s", data.google_container_cluster.gke-cluster.endpoint)
    token = data.google_client_config.current.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.gke-cluster.master_auth[0].cluster_ca_certificate)
}
