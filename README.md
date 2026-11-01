# toto-terra-gke

Terraform that hosts Toto microservices on **Google Kubernetes Engine (GKE)**.

The Toto microservices (built on the [`totoms`](https://github.com/nicolasances/toto-microservice-sdk) SDK) normally live in two GCP projects managed by [`toto-terra`](https://github.com/nicolasances/toto-terra):
`<dev-project>` (dev) and `<prod-project>` (prod). This repo runs them instead on **one GKE cluster in a separate GCP project**, while they keep reading their secrets and pulling their images from those two projects.

Today it hosts `tome-ms-language`. Other services can be added the same way.

> Placeholders used in the docs: `<gke-project>` is the project hosting the cluster, `<dev-project>` and `<prod-project>` are the toto projects of each environment (see `local.environments` in `workloads/gke.tf`), and `<domain>` is the public domain.

## What this repo does

- **Creates the platform** (`cluster/`): a dedicated VPC, a GKE Autopilot cluster with private nodes, Cloud NAT for outbound traffic, and the public entry point (static IP, Cloud DNS zone, Google-managed TLS certificate).
- **Deploys the workloads** (`workloads/`): one namespace per environment (`dev`, `prod`), a shared public Gateway (one HTTPS load balancer for all services), and for each service a Deployment, a Service and an HTTPRoute.
- **Gives the pods a GCP identity** through Workload Identity. `toto-terra` grants that identity access to the secrets in `<dev-project>` and `<prod-project>`. No service account keys are involved.

Services are reachable at:

| Environment | Namespace | GCP project (secrets, images) | URL |
|---|---|---|---|
| dev | `dev` | <dev project> | `https://api.dev.dr.<domain>/<service base path>` |
| prod | `prod` | <prod project> | `https://api.dr.<domain>/<service base path>` |

For example, `https://api.dev.dr.<domain>/tomelang/...` reaches `tome-ms-language` in dev.

## Architecture

Diagram: [docs/diagrams/architecture.drawio](docs/diagrams/architecture.drawio)

> The diagrams are draw.io files in [`docs/diagrams/`](docs/diagrams). Open them with [app.diagrams.net](https://app.diagrams.net) or the draw.io extension for VS Code.

How a request flows:

1. The client resolves `api.dev.dr.<domain>`. The registrar delegates `dr.<domain>` to Cloud DNS, which answers with the Gateway's static IP.
2. The global external Application Load Balancer terminates TLS with the certificate from Certificate Manager. Plain HTTP is redirected to HTTPS.
3. The load balancer picks the HTTPRoute by host (environment) and path prefix (service), and sends the request to the Service's pods.
4. At startup, the pod reads its secrets from Secret Manager in `GCP_PID` (`<dev-project>` or `<prod-project>`). It uses Workload Identity to do so.
5. Outbound traffic to the internet (for example MongoDB) goes through Cloud NAT, with a fixed IP.

The full details are in [docs/architecture.md](docs/architecture.md).

## How it works with toto-terra

The two repos split responsibilities:

| | toto-terra-gke (this repo) | toto-terra |
|---|---|---|
| GCP project | `<gke-project>` |  |
| Owns | Network, cluster, DNS, certificates, Gateway, Kubernetes objects | Secrets, Artifact Registry, databases, Pub/Sub, buckets, ... |
| Identity | Creates the Kubernetes service account `<env>/<service>` | Grants IAM roles to that service account's principal |

The link between them is the pod's **Workload Identity principal**:

```
principal://iam.googleapis.com/projects/<gke-project-number>/locations/global/workloadIdentityPools/<gke-project>.svc.id.goog/subject/ns/<env>/sa/<service>
```

`toto-terra` builds this principal from `gke_project_id` and `gke_project_number`, which come from this repo's `cluster/` output `gke_project_number`. It then grants roles to it, for example `roles/secretmanager.secretAccessor`. See [docs/workload-identity.md](docs/workload-identity.md).

## Repository layout

```
cluster/      GCP platform: APIs, network, GKE cluster, DNS, certificates   (state: terraform/cluster)
workloads/    Kubernetes objects: namespaces, Gateway, services              (state: terraform/state)
scripts/      tf-env.template.sh: the TF_VAR_* to set before running Terraform
docs/         Architecture, Workload Identity, operations, diagrams
```

The two folders are separate Terraform roots. Both store their state in the GCS bucket `toto-terra-gke-dr`. `workloads/` reads the outputs of `cluster/` through `terraform_remote_state`.

## Quick start

Terraform runs from a GCP VM, using the VM's service account (Application Default Credentials):

```bash
# once: create your env file from the template, and protect it
cp scripts/tf-env.template.sh scripts/tf-env.dev.sh   # gitignored
chmod 600 scripts/tf-env.dev.sh

# every session
source scripts/tf-env.dev.sh

cd cluster   && terraform init && terraform apply   # 1. platform
cd ../workloads && terraform init && terraform apply   # 2. workloads (after toto-terra has granted access)
```

The first setup needs a few steps outside this repo: the state bucket, IAM grants, NS records at the registrar, and `toto-terra`. The full order is in [docs/operations.md](docs/operations.md).

## Documentation

- [docs/architecture.md](docs/architecture.md): every component, and why it is there
- [docs/workload-identity.md](docs/workload-identity.md): how pods get access to the toto projects
- [docs/operations.md](docs/operations.md): first setup, deploying a new version, adding a service, troubleshooting
- [docs/diagrams/](docs/diagrams): draw.io diagrams (architecture, Workload Identity, Terraform layout)
