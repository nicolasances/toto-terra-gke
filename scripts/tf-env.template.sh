
# Image tags (TF_VAR_*_image_tag) are only used when a Deployment is created
# (first apply, new environment, recreation). After that, CI in the service repo
# owns the image (kubectl set image) and changing them here has no effect.

# GCP project hosting the GKE cluster
export TF_VAR_gcp_pid="<gke-project-id>"

# GKE cluster (created in cluster/, used by workloads/).
# The Autopilot cluster is regional: its location is the region (gcp_region, default europe-west1)
export TF_VAR_gke_cluster_name="<cluster-name>"
export TF_VAR_gke_cluster_location="europe-west1"

# Public domain (bought at a registrar, DNS delegated to Cloud DNS by cluster/)
export TF_VAR_domain="<your-domain.com>"

# Image tag (package.json version) of tome-ms-language used when its Deployments are created
export TF_VAR_tome_ms_language_image_tag='{"dev":"1.1.0","prod":"1.1.0"}'

# Image tag (package.json version) of toto-ms-auth used when its Deployments are created
export TF_VAR_toto_ms_auth_image_tag='{"dev":"2.0.0","prod":"2.0.0"}'


# Image tag (package.json version) of toto-ms-supermarket used when its Deployments are created
export TF_VAR_toto_ms_supermarket_image_tag='{"dev":"<version>","prod":"<version>"}'

# URL of the Gale broker (still on Cloud Run) used by toto-ms-supermarket, per environment
export TF_VAR_toto_ms_supermarket_gale_broker_url='{"dev":"https://gale-broker-<cloud_run_endpoint_suffix>/galebroker","prod":"https://gale-broker-<cloud_run_endpoint_suffix>/galebroker"}'

# Image tag (package.json version) of toto-react-supermarket (toto-suppie) used when its Deployments are created
export TF_VAR_toto_react_supermarket_image_tag='{"dev":"<version>","prod":"<version>"}'
