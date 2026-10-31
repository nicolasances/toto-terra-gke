# ---------------------------------------------------------------
# 1. Node Service Account
# ---------------------------------------------------------------
# Dedicated, minimal identity for the nodes (instead of the default Compute Engine SA, which often has Editor).
# Pods do NOT use it: they use Workload Identity (see workloads/).
resource "google_service_account" "gke-nodes" {
    account_id = "gke-nodes"
    display_name = "GKE Nodes Service Account"
}
resource "google_project_iam_member" "gke-nodes-role-default-node" {
    project = var.gcp_pid
    role = "roles/container.defaultNodeServiceAccount"
    member = format("serviceAccount:%s", google_service_account.gke-nodes.email)
}

# ---------------------------------------------------------------
# 2. GKE Autopilot Cluster (regional, private nodes)
# ---------------------------------------------------------------
resource "google_container_cluster" "gke-cluster" {
    name = var.gke_cluster_name
    location = var.gcp_region

    enable_autopilot = true

    network = google_compute_network.gke-vpc.id
    subnetwork = google_compute_subnetwork.gke-subnet.id
    ip_allocation_policy {
        cluster_secondary_range_name = "gke-pods"
        services_secondary_range_name = "gke-services"
    }

    # Nodes have no public IP. The control plane keeps its public endpoint so the
    # Terraform VM (outside this VPC) can reach it; access still requires Google IAM + RBAC.
    private_cluster_config {
        enable_private_nodes = true
        enable_private_endpoint = false
    }

    cluster_autoscaling {
        auto_provisioning_defaults {
            service_account = google_service_account.gke-nodes.email
            oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
        }
    }

    release_channel {
        channel = "REGULAR"
    }

    # Terraform refuses to destroy (or replace) the cluster while this is true
    deletion_protection = true

    depends_on = [
        google_project_service.container-api,
        google_project_iam_member.gke-nodes-role-default-node,
        google_compute_router_nat.gke-nat,
    ]
}
