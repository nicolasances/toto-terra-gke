# Needed by toto-terra to build the Workload Identity principals of the pods
output "gke_project_number" {
    value = data.google_project.current.number
}
output "gke_workload_pool" {
    value = google_container_cluster.gke-cluster.workload_identity_config[0].workload_pool
}
# Outbound IP of all pods, e.g. to allowlist on Mongo
output "gke_nat_ip" {
    value = google_compute_address.gke-nat-ip.address
}
