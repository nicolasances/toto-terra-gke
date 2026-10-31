# ---------------------------------------------------------------
# Terraform variables for toto-terra-gke.
#
# This is a TEMPLATE: never put real values in it, it is committed to git.
# Install a private copy outside the repo (only readable by your user):
#
#   install -d -m 700 ~/.config/toto-terra-gke
#   install -m 600 tf-env.template.sh ~/.config/toto-terra-gke/tf-env.sh
#
# then edit ~/.config/toto-terra-gke/tf-env.sh with an editor
# (not with echo/cat >>, which leaves the values in the shell history).
#
# The file is loaded at login by the snippet in tf-env.bashrc.sh.
# ---------------------------------------------------------------

# GCP project hosting the GKE cluster
export TF_VAR_gcp_pid="<gke-project-id>"

# Existing GKE cluster
export TF_VAR_gke_cluster_name="<cluster-name>"
export TF_VAR_gke_cluster_location="<cluster-region-or-zone>"

# Image tag (package.json version) of tome-ms-language deployed in each environment
export TF_VAR_tome_ms_language_image_tag='{"dev":"1.0.0","prod":"1.0.0"}'
