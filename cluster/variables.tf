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
# ---------------------------------------------------------------
# 2. GKE Variables
# ---------------------------------------------------------------
variable "gke_cluster_name" {
    description = "Name of the GKE cluster"
    type = string
}
