# ---------------------------------------------------------------
# 1. VPC & Subnet
# ---------------------------------------------------------------
resource "google_compute_network" "gke-vpc" {
    name = "gke-vpc"
    auto_create_subnetworks = false
    depends_on = [google_project_service.compute-api]
}
resource "google_compute_subnetwork" "gke-subnet" {
    name = "gke-subnet"
    region = var.gcp_region
    network = google_compute_network.gke-vpc.id
    ip_cidr_range = "10.10.0.0/20"

    # Lets private nodes reach Google APIs (Secret Manager, Artifact Registry, ...) without going through NAT
    private_ip_google_access = true

    secondary_ip_range {
        range_name = "gke-pods"
        ip_cidr_range = "10.20.0.0/14"
    }
    secondary_ip_range {
        range_name = "gke-services"
        ip_cidr_range = "10.30.0.0/20"
    }
}

# ---------------------------------------------------------------
# 2. Cloud NAT: outbound internet access for private nodes (e.g. Mongo),
#    through a static IP that can be allowlisted
# ---------------------------------------------------------------
resource "google_compute_router" "gke-router" {
    name = "gke-router"
    region = var.gcp_region
    network = google_compute_network.gke-vpc.id
}
resource "google_compute_address" "gke-nat-ip" {
    name = "gke-nat-ip"
    region = var.gcp_region
    depends_on = [google_project_service.compute-api]
}
resource "google_compute_router_nat" "gke-nat" {
    name = "gke-nat"
    router = google_compute_router.gke-router.name
    region = var.gcp_region

    nat_ip_allocate_option = "MANUAL_ONLY"
    nat_ips = [google_compute_address.gke-nat-ip.self_link]

    source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
    subnetwork {
        name = google_compute_subnetwork.gke-subnet.id
        source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }

    log_config {
        enable = true
        filter = "ERRORS_ONLY"
    }
}
