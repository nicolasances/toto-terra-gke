
# GCP project hosting the GKE cluster
export TF_VAR_gcp_pid="<gke-project-id>"

# Existing GKE cluster
export TF_VAR_gke_cluster_name="<cluster-name>"
export TF_VAR_gke_cluster_location="<cluster-region-or-zone>"

# Image tag (package.json version) of tome-ms-language deployed in each environment
export TF_VAR_tome_ms_language_image_tag='{"dev":"1.0.0","prod":"1.0.0"}'
