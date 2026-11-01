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

# Values of the 4 NS records "dr" to create in the parent zone (registrar today)
output "domain_name_servers" {
    value = google_dns_managed_zone.domain-zone.name_servers
}
# Used by workloads/ (through terraform_remote_state) to create the Gateway and the routes
output "gateway_ip_name" {
    value = google_compute_global_address.gateway-ip.name
}
output "gateway_ip" {
    value = google_compute_global_address.gateway-ip.address
}
output "gateway_certmap_name" {
    value = google_certificate_manager_certificate_map.gateway-certmap.name
}
output "env_hostnames" {
    value = local.env_hostnames
}
