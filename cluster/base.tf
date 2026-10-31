terraform {
    required_providers {
        google = {
            source = "hashicorp/google"
            version = "7.15.0"
        }
    }
    backend "gcs" {
        bucket = "toto-terra-gke-dr"
        prefix = "terraform/cluster"
    }
}

# Credentials come from the environment (Application Default Credentials):
# on the Terraform VM, that is the VM's attached service account
provider "google" {
    project = var.gcp_pid
    region = var.gcp_region
}

# ---------------------------------------------------------------
# APIs needed by the cluster
# ---------------------------------------------------------------
resource "google_project_service" "compute-api" {
    service = "compute.googleapis.com"
    disable_on_destroy = false
}
resource "google_project_service" "container-api" {
    service = "container.googleapis.com"
    disable_on_destroy = false
}

data "google_project" "current" {}
