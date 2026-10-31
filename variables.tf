# ---------------------------------------------------------------
# 1. GCP Project Variables
# ---------------------------------------------------------------
variable "gcp_pid" {
  description = "GCP Project ID"
  type = string
}
variable "gcp_region" {
    description = "GCP Region"
    type = string
    default = "europe-west1"
}
variable "gcp_zone" {
    description = "GCP Zone"
    type = string
    default = "europe-west1-c"
}
variable "gcp_service_account_key" {
    description = "Terraform Service Account key"
    type = string
    sensitive = true
}
# ---------------------------------------------------------------
# 2. GKE Variables
# ---------------------------------------------------------------
variable "gke_cluster_name" {
    description = "Name of the existing GKE cluster"
    type = string
}
variable "gke_cluster_location" {
    description = "Location of the existing GKE cluster (region for regional clusters, zone for zonal ones)"
    type = string
}
