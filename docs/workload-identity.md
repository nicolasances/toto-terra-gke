# Workload Identity: access from GKE to the toto projects

Diagram: [diagrams/workload-identity.drawio](diagrams/workload-identity.drawio)

## The problem

A pod runs as a **Kubernetes** service account (for example `dev/tome-ms-language`). Google IAM has never heard of it, but the pod has to read secrets in **another** GCP project (`<dev-project>`).

## The pool

A Workload Identity pool is a set of identities that Google IAM trusts even though Google did not create them. For GKE:

- it is named `<gke-project>.svc.id.goog` (`terraform output gke_workload_pool`), and exists automatically. Autopilot always enables it.
- it trusts tokens signed by the clusters of `<gke-project>`
- every Kubernetes service account becomes a principal in it:

```
principal://iam.googleapis.com/projects/<gke-project-number>/locations/global/workloadIdentityPools/<gke-project>.svc.id.goog/subject/ns/<namespace>/sa/<ksa>
                                         └ project that owns the pool ┘                           └ the pool ─────────────┘ └ who, inside it ─┘
```

## What happens at runtime

1. The SDK asks for Application Default Credentials. Inside GKE, this reaches the **GKE metadata server** on the node.
2. The metadata server gets a Kubernetes token for the pod's service account and exchanges it at Google's **Security Token Service**. STS validates it against the pool.
3. STS returns a short-lived Google access token for the principal `ns/dev/sa/tome-ms-language`.
4. The pod calls Secret Manager in `<dev-project>` with that token.
5. Secret Manager checks IAM in `<dev-project>`: this principal has `secretAccessor`, so the call is allowed.

There is no Google service account and no key to rotate or leak.

## Who configures what

| Step | Where |
|---|---|
| Create the Kubernetes service account `<service>` in `dev` and `prod`, and run the pod as it | this repo, `workloads/<service>.tf` |
| Grant roles to the principal in `<dev-project>` / `<prod-project>` | `toto-terra`, `<service>.tf` (applied once per environment) |

In `toto-terra`, `tome-ms-language.tf` builds the principal from:

- `gke_project_id`: the ID of `<gke-project>`
- `gke_project_number`: `terraform output gke_project_number` in `cluster/`
- `toto_environment`: the namespace (`dev` for `<dev-project>`, `prod` for `<prod-project>`)

and grants `roles/secretmanager.secretAccessor` on the project.

A service that needs more than secrets (Vertex AI, Cloud Storage, Pub/Sub, ...) needs more grants to the same principal in `toto-terra`.

## Things to know

- **The identity is namespace + service account name**, and the pool is shared by **all clusters of `<gke-project>`**. A pod running as `dev/tome-ms-language` in any cluster of that project gets the same access. Don't reuse a service account name for a workload that shouldn't have that access.
- **Grants are project-wide.** `secretAccessor` on the project lets the pod read every secret in it, not only its own. Narrow it to individual secrets in `toto-terra` if that matters.
- **dev and prod are isolated by namespace:** `dev/...` is only granted in `<dev-project>`, and `prod/...` only in `<prod-project>`.
