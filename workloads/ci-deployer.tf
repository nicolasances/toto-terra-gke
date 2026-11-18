# ---------------------------------------------------------------
# CI deployer: lets GitHub Actions in the service repos roll out new images
# (`kubectl set image` + `kubectl rollout status`).
#
# CI authenticates with the toto-cicd Google service account of each toto
# project (JSON key stored by toto-terra as the GitHub secret CICD_SERVICE_ACCOUNT).
# On GKE, a Google service account authenticates to Kubernetes with its email as
# the username, so the RBAC subject is a User named after that email.
#
# Each SA is bound only in its own environment's namespace:
#   toto-cicd@<dev project>  -> namespace dev
#   toto-cicd@<prod project> -> namespace prod
#
# To fetch cluster credentials, the SAs also need roles/container.clusterViewer
# on the GKE project. That grant is manual (see docs/operations.md).
# ---------------------------------------------------------------
resource "kubernetes_role_v1" "ci-deployer" {
    for_each = local.environments

    metadata {
        name = "ci-deployer"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }

    # Update the image of a Deployment and watch the rollout
    rule {
        api_groups = ["apps"]
        resources = ["deployments"]
        verbs = ["get", "list", "watch", "patch"]
    }

    # Read-only, for `kubectl rollout status` and debugging from CI
    rule {
        api_groups = ["apps"]
        resources = ["replicasets"]
        verbs = ["get", "list", "watch"]
    }
    rule {
        api_groups = [""]
        resources = ["pods"]
        verbs = ["get", "list", "watch"]
    }
}

resource "kubernetes_role_binding_v1" "ci-deployer" {
    for_each = local.environments

    metadata {
        name = "ci-deployer"
        namespace = kubernetes_namespace_v1.env-namespace[each.key].metadata[0].name
    }
    role_ref {
        api_group = "rbac.authorization.k8s.io"
        kind = "Role"
        name = kubernetes_role_v1.ci-deployer[each.key].metadata[0].name
    }
    subject {
        api_group = "rbac.authorization.k8s.io"
        kind = "User"
        name = format("toto-cicd@%s.iam.gserviceaccount.com", each.value)
    }
}
