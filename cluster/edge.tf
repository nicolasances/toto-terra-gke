# ---------------------------------------------------------------
# Public entry point of the cluster: one static IP, one DNS zone and one
# certificate shared by all services. The Gateway (load balancer) itself is
# created in workloads/ and uses what is defined here.
# ---------------------------------------------------------------
locals {
    # Subdomain owned by this project: the parent zone (<domain>, at the registrar or in another
    # GCP project) delegates it here with NS records, so it can move without touching this repo
    subdomain = format("dr.%s", var.domain)

    # Public hostname of each environment. Services are routed by path (their basePath) on it,
    # e.g. https://api.dev.dr.<domain>/tomelang/...
    env_hostnames = {
        dev = format("api.dev.%s", local.subdomain)
        prod = format("api.%s", local.subdomain)
    }
}

# ---------------------------------------------------------------
# 1. Static IP of the Gateway
# ---------------------------------------------------------------
resource "google_compute_global_address" "gateway-ip" {
    name = "gke-gateway-ip"
    depends_on = [google_project_service.compute-api]
}

# ---------------------------------------------------------------
# 2. DNS zone of the subdomain
# ---------------------------------------------------------------
# The parent zone must delegate the subdomain with 4 NS records "dr" -> this zone's name_servers (see outputs).
# Do NOT change the domain's nameservers at the registrar: that would hand over the whole domain.
resource "google_dns_managed_zone" "domain-zone" {
    name = format("%s-zone", replace(local.subdomain, ".", "-"))
    dns_name = format("%s.", local.subdomain)
    depends_on = [google_project_service.dns-api]
}
resource "google_dns_record_set" "env-hostname" {
    for_each = local.env_hostnames

    managed_zone = google_dns_managed_zone.domain-zone.name
    name = format("%s.", each.value)
    type = "A"
    ttl = 300
    rrdatas = [google_compute_global_address.gateway-ip.address]
}

# ---------------------------------------------------------------
# 3. Google-managed certificate (Certificate Manager), validated through DNS
# ---------------------------------------------------------------
resource "google_certificate_manager_dns_authorization" "env-hostname" {
    for_each = local.env_hostnames

    name = format("%s-hostname-dns-auth", each.key)
    domain = each.value
    depends_on = [google_project_service.certificatemanager-api]
}
resource "google_dns_record_set" "env-hostname-dns-auth" {
    for_each = local.env_hostnames

    managed_zone = google_dns_managed_zone.domain-zone.name
    name = google_certificate_manager_dns_authorization.env-hostname[each.key].dns_resource_record[0].name
    type = google_certificate_manager_dns_authorization.env-hostname[each.key].dns_resource_record[0].type
    ttl = 300
    rrdatas = [google_certificate_manager_dns_authorization.env-hostname[each.key].dns_resource_record[0].data]
}
resource "google_certificate_manager_certificate" "gateway-cert" {
    name = "gke-gateway-cert"
    managed {
        domains = values(local.env_hostnames)
        dns_authorizations = [for auth in google_certificate_manager_dns_authorization.env-hostname : auth.id]
    }
}

# The Gateway references this map (annotation networking.gke.io/certmap) to pick the certificate per hostname
resource "google_certificate_manager_certificate_map" "gateway-certmap" {
    name = "gke-gateway-certmap"
    depends_on = [google_project_service.certificatemanager-api]
}
resource "google_certificate_manager_certificate_map_entry" "env-hostname" {
    for_each = local.env_hostnames

    name = format("%s-hostname", each.key)
    map = google_certificate_manager_certificate_map.gateway-certmap.name
    hostname = each.value
    certificates = [google_certificate_manager_certificate.gateway-cert.id]
}
