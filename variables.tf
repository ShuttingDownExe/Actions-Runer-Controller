# =============================================================================
# Variables for AKS + GitHub Actions Runner Controller deployment
# =============================================================================

# ------------------ General ------------------

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-actions-runner-controller"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    environment = "shared"
    managed_by  = "terraform"
    purpose     = "github-actions-runners"
  }
}

# ------------------ AKS Cluster ------------------

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-gh-runners"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = null # Uses latest stable if null
}

variable "sku_tier" {
  description = "AKS SKU tier. Use 'Free' for cost savings, 'Standard' for SLA."
  type        = string
  default     = "Free"
}

# ------------------ System Node Pool ------------------

variable "system_node_vm_size" {
  description = "VM size for the system node pool (runs ARC controller + kube-system)"
  type        = string
  default     = "Standard_B2s" # 2 vCPU, 4 GiB — cheapest burstable
}

variable "system_node_count" {
  description = "Number of nodes in the system pool"
  type        = number
  default     = 1
}

# ------------------ Runner Node Pool ------------------

variable "runner_node_vm_size" {
  description = "VM size for the runner node pool (runs GitHub Actions jobs)"
  type        = string
  default     = "Standard_B2ms" # 2 vCPU, 8 GiB — cheap burstable with more RAM
}

variable "runner_node_min_count" {
  description = "Minimum node count for runner pool (0 = scale to zero nodes)"
  type        = number
  default     = 0
}

variable "runner_node_max_count" {
  description = "Maximum node count for runner pool"
  type        = number
  default     = 3
}

variable "runner_node_use_spot" {
  description = "Use Azure Spot instances for runner nodes (up to 90% cheaper)"
  type        = bool
  default     = true
}

variable "runner_spot_max_price" {
  description = "Maximum price per hour for spot instances (-1 = on-demand price cap)"
  type        = number
  default     = -1
}

variable "runner_node_labels" {
  description = "Labels to apply to runner nodes"
  type        = map(string)
  default = {
    "workload" = "github-runner"
  }
}

variable "runner_node_taints" {
  description = "Taints for runner node pool to ensure only runners land here"
  type        = list(string)
  default     = ["workload=github-runner:NoSchedule"]
}

# ------------------ ACR (Container Registry) ------------------

variable "acr_name" {
  description = "Name of the Azure Container Registry (must be globally unique, alphanumeric only)"
  type        = string
}

variable "acr_sku" {
  description = "SKU for the Azure Container Registry"
  type        = string
  default     = "Basic" # Cheapest tier
}

# ------------------ GitHub ARC ------------------

variable "arc_controller_namespace" {
  description = "Kubernetes namespace for the ARC controller"
  type        = string
  default     = "arc-systems"
}

variable "arc_runner_namespace" {
  description = "Kubernetes namespace for the runner scale sets"
  type        = string
  default     = "arc-runners"
}

variable "arc_controller_chart_version" {
  description = "Version of the gha-runner-scale-set-controller Helm chart"
  type        = string
  default     = "0.10.1"
}

variable "github_config_url" {
  description = "GitHub repository or organization URL for the runners (e.g. https://github.com/myorg)"
  type        = string
}

# -- Authentication (GitHub App — recommended) --

variable "github_app_id" {
  description = "GitHub App ID for ARC authentication"
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID (found in org settings → Installed GitHub Apps)"
  type        = string
  default     = ""
}

variable "github_app_private_key_path" {
  description = "Path to the GitHub App private key PEM file"
  type        = string
  default     = ""
}

# -- Authentication (PAT — fallback, not recommended for production) --

variable "github_pat" {
  description = "GitHub PAT (only if NOT using a GitHub App). Requires repo or admin:org scope."
  type        = string
  sensitive   = true
  default     = ""
}

variable "runner_scale_set_name" {
  description = "Name of the runner scale set (used as the runs-on label in workflows)"
  type        = string
  default     = "arc-runner-set"
}

variable "runner_min_count" {
  description = "Minimum number of idle runner pods (0 = scale to zero pods)"
  type        = number
  default     = 0
}

variable "runner_max_count" {
  description = "Maximum number of concurrent runner pods"
  type        = number
  default     = 5
}

variable "custom_runner_image" {
  description = "Full image reference for the custom runner (e.g. myacr.azurecr.io/actions-runner-custom:latest). If empty, built from acr_name."
  type        = string
  default     = ""
}

variable "runner_image_tag" {
  description = "Tag for the custom runner image"
  type        = string
  default     = "latest"
}
