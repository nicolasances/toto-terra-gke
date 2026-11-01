# Architecture

Diagram: [diagrams/architecture.drawio](diagrams/architecture.drawio)

Everything below lives in one GCP project, `<gke-project>`, in region `europe-west1`. The exceptions are the secrets and images, which stay in `<dev-project>` and `<prod-project>`, managed by `toto-terra`.

## 1. Network (`cluster/network.tf`)

| Resource | Value | Why |
|---|---|---|
| VPC `gke-vpc` | no auto subnets | Keeps the cluster isolated from the rest of the project |
| Subnet `gke-subnet` | `10.10.0.0/20` | Node IPs |
| Secondary range `gke-pods` | `10.20.0.0/14` | Pod IPs (VPC-native cluster) |
| Secondary range `gke-services` | `10.30.0.0/20` | ClusterIP Service IPs |
| Private Google Access | on | Private nodes reach Google APIs (Secret Manager, Artifact Registry, ...) without a public IP |
| Cloud Router + Cloud NAT `gke-nat` | static IP `gke-nat-ip` | Outbound internet for private nodes (MongoDB, external APIs) from one fixed IP that can be allowlisted (`terraform output gke_nat_ip`) |

## 2. Cluster (`cluster/gke.tf`)

- **GKE Autopilot**, regional. Google manages the nodes, and you pay per pod request, so there is no node pool to size. Nodes are created on demand from the pods' `resources.requests`.
- **Private nodes, public control plane.** Nodes have no public IP. The control plane endpoint stays public so the Terraform VM can reach it, but access still requires Google IAM and Kubernetes RBAC.
- **Node service account `gke-nodes`.** A minimal identity for the nodes, used instead of the default Compute Engine account. Pods don't use it: they use Workload Identity.
- **Workload Identity** is always on in Autopilot. The pool is `<gke-project>.svc.id.goog` (see [workload-identity.md](workload-identity.md)).
- **Gateway API** (`CHANNEL_STANDARD`) installs the Gateway CRDs and the GKE Gateway controller.
- **Release channel `REGULAR`** and `deletion_protection = true`.

## 3. Public entry point (`cluster/edge.tf` + `workloads/gke.tf`)

All services and environments share **one** load balancer.

```
<domain> (registrar) ──NS "dr"──▶ Cloud DNS zone dr.<domain>
                                     ├─ A api.dev.dr.<domain> ─┐
                                     └─ A api.dr.<domain> ─────┴─▶ static IP gke-gateway-ip
                                                                    │
                                     Global external Application LB (Gateway public-gateway)
                                       :80  → 301 to https
                                       :443 → TLS (cert map gke-gateway-certmap)
                                              ├─ host api.dev.dr.<domain> + /tomelang → dev/tome-ms-language
                                              └─ host api.dr.<domain>     + /tomelang → prod/tome-ms-language
```

- **DNS.** The parent domain stays at the registrar. Only the subdomain `dr.<domain>` is delegated to Cloud DNS, through 4 NS records named `dr` at the registrar (`terraform output domain_name_servers`). The delegation can later move to another GCP project without touching the parent domain.
- **Certificate.** A Google-managed certificate covering both hostnames, validated by DNS authorization: Terraform writes the validation CNAME records into the Cloud DNS zone. A certificate map lets the Gateway pick it per hostname.
- **Gateway** (`workloads/gke.tf`, namespace `gateway`). The Kubernetes object that the GKE controller turns into the load balancer. It uses the static IP (`NamedAddress`) and the certificate map (annotation `networking.gke.io/certmap`), both read from `cluster/` outputs.
  - Listener `https` (443) accepts routes only from the `dev` and `prod` namespaces.
  - Listener `http` (80) only serves the `http-to-https` redirect.
- **HTTPRoute per service and environment.** It attaches to the `https` listener, matches the environment's hostname plus the service's base path (`PathPrefix /tomelang`), and forwards to the service's ClusterIP Service.
- **HealthCheckPolicy per service.** The load balancer checks `/` by default, and the services only answer on `/health`.

Why a Gateway rather than a `LoadBalancer` Service per service: one IP, one certificate and one load balancer for everything. A new service only adds an HTTPRoute.

## 4. Workloads (`workloads/`)

| Object | Per | Notes |
|---|---|---|
| Namespace `dev`, `prod` | environment | `local.environments` maps env → GCP project (`<dev-project>`, `<prod-project>`) |
| ServiceAccount `<service>` | service × env | Its name and namespace form the pod's GCP identity |
| ConfigMap `<service>-config` | service × env | `HYPERSCALER=gcp`, `GCP_PID=<env project>`, loaded through `envFrom` |
| Deployment `<service>` | service × env | Image `europe-west1-docker.pkg.dev/<env project>/<service>/<service>:<tag>`, probes on `/health`, requests and limits |
| Service `<service>` | service × env | ClusterIP, port 80 → container port `http` (8080) |
| HTTPRoute + HealthCheckPolicy | service × env | See above |

The **image tag** comes from `TF_VAR_tome_ms_language_image_tag`, for example `{"dev":"1.2.0","prod":"1.1.0"}`. Deploying is a Terraform apply.

**Images** are pulled from the environment's Artifact Registry repository, which `toto-terra` makes publicly readable. That is why the nodes need no registry permission.

## 5. Secrets and configuration

The `totoms` SDK reads its secrets from `projects/$GCP_PID/secrets/<name>` at startup, before it starts listening, with fixed names (`mongo-host`, `jwt-signing-key`, ...). Setting `GCP_PID` per namespace is what points `dev` to `<dev-project>` and `prod` to `<prod-project>`. The secrets never leave those projects, and nothing secret is stored in this repo or in Kubernetes.

## 6. Who runs Terraform

A GCP VM (`terra`) with Application Default Credentials from its service account, so no key file is involved. The VM needs the `cloud-platform` access scope; the actual permissions are restricted by IAM on that service account. The state and its lock live in the GCS bucket `toto-terra-gke-dr`. See [diagrams/terraform-layout.drawio](diagrams/terraform-layout.drawio) and [operations.md](operations.md).
