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
# Workload Identity: the Pub/Sub scaler reads the subscription backlog
# from Cloud Monitoring, as the keda-operator service account of the chart.
# principal://.../subject/ns/keda/sa/keda-operator
# ---------------------------------------------------------------
resource "google_project_iam_member" "keda-operator-monitoring-viewer" {
    project = var.gcp_pid
    role = "roles/monitoring.viewer"
    member = format(
        "principal://iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s.svc.id.goog/subject/ns/%s/sa/keda-operator",
        data.terraform_remote_state.cluster.outputs.gke_project_number,
        var.gcp_pid,
        kubernetes_namespace_v1.keda.metadata[0].name,
    )
}
