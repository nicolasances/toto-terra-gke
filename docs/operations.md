# Operations

Diagram: [diagrams/terraform-layout.drawio](diagrams/terraform-layout.drawio)

## First setup (in order)

**0. Manual prerequisites (once)**

- Create the GCS bucket `toto-terra-gke-dr` (Terraform state).
- Create the Terraform VM:
  - access scope `cloud-platform`
  - a service account with rights on the bucket and on what Terraform manages in the project (compute, container, DNS, Certificate Manager, service accounts)
- Create your env file from `scripts/tf-env.template.sh` (e.g. `scripts/tf-env.dev.sh`, gitignored), run `chmod 600` on it, and `source` it in every session. It contains no secrets, only names and versions.

**1. `cluster/`**

```bash
cd cluster && terraform init && terraform apply
```

The VM does not have IAM admin rights on the project, so after the first apply, grant these by hand (Console or gcloud):

```bash
gcloud projects add-iam-policy-binding <gke-project> \
  --member="serviceAccount:gke-nodes@<gke-project>.iam.gserviceaccount.com" \
  --role="roles/container.defaultNodeServiceAccount"
```

Also give the VM's service account `roles/iam.serviceAccountUser` on `gke-nodes`, so it can create a cluster whose nodes run as it.

**2. Registrar.** Create 4 NS records named `dr` with the values of `terraform output domain_name_servers`. Do **not** change the domain's own nameservers. Until the delegation has propagated, the certificate stays `PROVISIONING`.

**3. toto-terra.** Set `gke_project_id` and `gke_project_number` (`terraform output gke_project_number`), then apply on `<dev-project>` and on `<prod-project>`. This grants the pods access to their secrets.

**4. `workloads/`**

```bash
cd workloads && terraform init && terraform apply
```

## Deploy a new version of a service

1. Make sure the image `<version>` exists in the environment's Artifact Registry.
2. Update the tag in your env file, e.g. `TF_VAR_tome_ms_language_image_tag='{"dev":"1.3.0","prod":"1.2.0"}'`, then `source` it.
3. `cd workloads && terraform apply`. Only the Deployment of the changed environment should be updated.

Caution: the Artifact Registry cleanup policy in `toto-terra` deletes images older than 7 days. A pinned tag that gets deleted breaks the next pod restart. Raise `keep_count` there, or exclude released tags.

## Add a new service

1. **This repo:** copy `workloads/tome-ms-language.tf` to `workloads/<service>.tf` and rename everything:
   - resource names, KSA, ConfigMap, Deployment, Service
   - image path and the `<service>_image_tag` variable
   - the HTTPRoute `PathPrefix`, which must be the service's base path
   Add the tag variable to `scripts/tf-env.template.sh` and your env file.
2. **toto-terra:** in `<service>.tf`, build the principal `ns/<env>/sa/<service>` (same pattern as `tome_ms_language_gke_principal`) and grant it the roles the service needs, at least `secretAccessor`. Apply on both projects.
3. Apply `workloads/`.

## Check what runs

```bash
gcloud container clusters get-credentials <cluster-name> --region europe-west1 --project <gke-project>

kubectl get all -n dev
kubectl logs -n dev deploy/tome-ms-language
kubectl get gateway,httproute -A
kubectl describe httproute tome-ms-language -n dev          # accepted by the Gateway?
gcloud certificate-manager certificates describe gke-gateway-cert   # ACTIVE?

# Test without the Gateway
kubectl port-forward -n dev svc/tome-ms-language 8080:80
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `terraform init` in the repo root says the directory is empty | Run it in `cluster/` or `workloads/` |
| `workloads/` plan: cluster not found | Apply `cluster/` first, and check `TF_VAR_gke_cluster_location` (the region) |
| GCS state lock 403 "Provided scope(s) are not authorized" | The VM's access scope isn't `cloud-platform`: stop the VM, change the scope, restart it |
| 403 on `google_project_iam_member` | The VM has no IAM admin rights by design: grant the role by hand (see step 1) |
| Certificate `PROVISIONING`, `CNAME_MISMATCH` | DNS delegation not propagated yet: check `dig NS dr.<domain>` and the `_acme-challenge` CNAME, then wait |
| Pod crashes at startup with a permission error on secrets | `toto-terra` grant missing or wrong principal (project number, namespace, KSA name) |
| `kubectl logs` shows nothing | Pass the namespace: `-n dev` / `-n prod` |
| 502 / no healthy upstream from the Gateway | Health check failing: check the HealthCheckPolicy and that `/health` answers on the container port |
