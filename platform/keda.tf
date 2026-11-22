# ---------------------------------------------------------------
# KEDA: event-driven autoscaler. Scales the agents' ScaledJobs from the
# Pub/Sub backlog (see workloads/agent-coder.tf).
#
# This is a separate Terraform root from workloads/ on purpose: the KEDA CRDs
# (ScaledJob, TriggerAuthentication) must exist when workloads/ is *planned*,
# because kubernetes_manifest needs the CRD schema at plan time. Apply order:
# cluster/ -> platform/ -> workloads/.
# ---------------------------------------------------------------
variable "keda_chart_version" {
    description = "Version of the official KEDA Helm chart (https://kedacore.github.io/charts). Pinned: bump it deliberately"
    type = string
    default = "2.17.2"
}

resource "kubernetes_namespace_v1" "keda" {
    metadata {
        name = "keda"
    }
}

resource "helm_release" "keda" {
    name = "keda"
    namespace = kubernetes_namespace_v1.keda.metadata[0].name
    repository = "https://kedacore.github.io/charts"
    chart = "keda"
    version = var.keda_chart_version

    # Fail the apply (instead of returning early) if KEDA does not become ready:
    # workloads/ depends on its CRDs and on the admission webhook
    wait = true
    timeout = 600
}

# ---------------------------------------------------------------
# Workload Identity: the Pub/Sub scaler reads the subscription backlog from
# Cloud Monitoring, as the keda-operator service account of the chart:
# principal://.../subject/ns/keda/sa/keda-operator
#
# The role roles/monitoring.viewer on the GKE project is granted BY HAND, not here:
# the Terraform VM has no IAM admin rights (403 "Policy update access denied").
# See "platform/" in docs/operations.md.
# ---------------------------------------------------------------
