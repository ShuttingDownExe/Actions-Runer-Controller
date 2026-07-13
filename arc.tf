# =============================================================================
# GitHub Actions Runner Controller (ARC) — Helm Deployments
# =============================================================================

locals {
  runner_image = var.custom_runner_image != "" ? var.custom_runner_image : "${azurerm_container_registry.acr.login_server}/actions-runner-custom:${var.runner_image_tag}"

  # Auth method: GitHub App (recommended) vs PAT (fallback)
  # Private key can come from a file (local) or base64 variable (CI/CD)
  has_private_key = var.github_app_private_key_path != "" || var.github_app_private_key_base64 != ""
  use_github_app  = var.github_app_id != "" && var.github_app_installation_id != "" && local.has_private_key
  use_pat         = var.github_pat != ""

  github_app_private_key = (
    var.github_app_private_key_base64 != "" ? base64decode(var.github_app_private_key_base64) :
    var.github_app_private_key_path != "" ? file(var.github_app_private_key_path) :
    ""
  )
}

# ------------------ Auth Validation ------------------

resource "terraform_data" "auth_validation" {
  lifecycle {
    precondition {
      condition     = local.use_github_app || local.use_pat
      error_message = "You must provide either GitHub App credentials (github_app_id + github_app_installation_id + private key file/base64) or a github_pat."
    }
    precondition {
      condition     = !(local.use_github_app && local.use_pat)
      error_message = "Provide EITHER GitHub App credentials OR a PAT, not both."
    }
  }
}

# ------------------ ARC Controller ------------------
# Installs the CRDs + controller that manages AutoScalingRunnerSets

resource "helm_release" "arc_controller" {
  name             = "arc-controller"
  namespace        = var.arc_controller_namespace
  create_namespace = true
  chart            = "oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
  version          = var.arc_controller_chart_version
  wait             = true
  timeout          = 300

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_kubernetes_cluster_node_pool.runners,
  ]
}

# ------------------ Runner Scale Set (Custom Helm Chart) ------------------
# Uses our local chart in ./charts/arc-custom-runner

resource "helm_release" "arc_runner_set" {
  name             = var.runner_scale_set_name
  namespace        = var.arc_runner_namespace
  create_namespace = true
  chart            = "${path.module}/charts/arc-custom-runner"
  wait             = true
  timeout          = 300

  # GitHub config
  set {
    name  = "githubConfigUrl"
    value = var.github_config_url
  }

  # ---------- GitHub App Auth (recommended) ----------
  dynamic "set_sensitive" {
    for_each = local.use_github_app ? [1] : []
    content {
      name  = "githubConfigSecret.github_app_id"
      value = var.github_app_id
    }
  }

  dynamic "set_sensitive" {
    for_each = local.use_github_app ? [1] : []
    content {
      name  = "githubConfigSecret.github_app_installation_id"
      value = var.github_app_installation_id
    }
  }

  dynamic "set_sensitive" {
    for_each = local.use_github_app ? [1] : []
    content {
      name  = "githubConfigSecret.github_app_private_key"
      value = local.github_app_private_key
    }
  }

  # ---------- PAT Auth (fallback) ----------
  dynamic "set_sensitive" {
    for_each = local.use_pat ? [1] : []
    content {
      name  = "githubConfigSecret.github_token"
      value = var.github_pat
    }
  }

  # Custom runner image (Azure CLI + Terraform pre-installed)
  set {
    name  = "runnerImage.repository"
    value = split(":", local.runner_image)[0]
  }

  set {
    name  = "runnerImage.tag"
    value = var.runner_image_tag
  }

  # Scale-to-zero configuration
  set {
    name  = "minRunners"
    value = var.runner_min_count
  }

  set {
    name  = "maxRunners"
    value = var.runner_max_count
  }

  # Schedule runners on the spot node pool
  set {
    name  = "nodeSelector.workload"
    value = "github-runner"
  }

  # Tolerate the spot + runner taints
  set {
    name  = "tolerations[0].key"
    value = "workload"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Equal"
  }
  set {
    name  = "tolerations[0].value"
    value = "github-runner"
  }
  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }
  set {
    name  = "tolerations[1].key"
    value = "kubernetes.azure.com/scalesetpriority"
  }
  set {
    name  = "tolerations[1].operator"
    value = "Equal"
  }
  set {
    name  = "tolerations[1].value"
    value = "spot"
  }
  set {
    name  = "tolerations[1].effect"
    value = "NoSchedule"
  }

  # Resource limits — keep runners lean
  set {
    name  = "resources.requests.cpu"
    value = "250m"
  }
  set {
    name  = "resources.requests.memory"
    value = "512Mi"
  }
  set {
    name  = "resources.limits.cpu"
    value = "1500m"
  }
  set {
    name  = "resources.limits.memory"
    value = "3Gi"
  }

  depends_on = [
    helm_release.arc_controller,
    azurerm_role_assignment.aks_acr_pull,
    null_resource.build_runner_image,
    terraform_data.auth_validation,
  ]
}
