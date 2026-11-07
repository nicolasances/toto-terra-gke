
# GCP project hosting the GKE cluster
export TF_VAR_gcp_pid="<gke-project-id>"

# GKE cluster (created in cluster/, used by workloads/).
# The Autopilot cluster is regional: its location is the region (gcp_region, default europe-west1)
export TF_VAR_gke_cluster_name="<cluster-name>"
export TF_VAR_gke_cluster_location="europe-west1"

# Public domain (bought at a registrar, DNS delegated to Cloud DNS by cluster/)
export TF_VAR_domain="<your-domain.com>"

# Image tag (package.json version) of tome-ms-language deployed in each environment
export TF_VAR_tome_ms_language_image_tag='{"dev":"1.0.1","prod":"1.0.1"}'
