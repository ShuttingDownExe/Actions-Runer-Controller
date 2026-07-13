# =============================================================================
# AKS Cluster + ACR for GitHub Actions Runner Controller
# Cost-optimized: Free tier, burstable VMs, spot instances, scale-to-zero
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# ------------------ Providers ------------------

provider "azurerm" {
  features {}
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

# ------------------ Resource Group ------------------

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ------------------ Azure Container Registry ------------------

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

# ------------------ Build & Push Custom Runner Image ------------------
# Uses "az acr build" to build the Dockerfile directly inside ACR.
# No local Docker daemon required — the build runs as an ACR Task in Azure.
# Automatically rebuilds when the Dockerfile content changes.

resource "null_resource" "build_runner_image" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/Dockerfile")
    acr_login_server = azurerm_container_registry.acr.login_server
    image_tag        = var.runner_image_tag
  }

  provisioner "local-exec" {
    command = <<-EOT
      az acr build \
        --registry ${var.acr_name} \
        --image actions-runner-custom:${var.runner_image_tag} \
        --file ${path.module}/Dockerfile \
        ${path.module} \
        --no-logs \
        --only-show-errors
    EOT
  }

  depends_on = [azurerm_container_registry.acr]
}

# ------------------ AKS Cluster ------------------

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  # System node pool — minimal, just runs kube-system + ARC controller
  default_node_pool {
    name                = "system"
    vm_size             = var.system_node_vm_size
    node_count          = var.system_node_count
    os_disk_size_gb     = 30 # Minimum to save cost
    os_disk_type        = "Managed"
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }
}

# ------------------ Runner Node Pool (Spot / Scale-to-zero) ------------------

resource "azurerm_kubernetes_cluster_node_pool" "runners" {
  name                  = "runners"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = var.runner_node_vm_size
  os_disk_size_gb       = 30
  os_disk_type          = "Managed"

  # Autoscaling — scale down to 0 nodes when no jobs
  auto_scaling_enabled  = true
  min_count             = var.runner_node_min_count
  max_count             = var.runner_node_max_count

  # Spot instances for massive cost savings
  priority        = var.runner_node_use_spot ? "Spot" : "Regular"
  eviction_policy = var.runner_node_use_spot ? "Delete" : null
  spot_max_price  = var.runner_node_use_spot ? var.runner_spot_max_price : null

  node_labels = var.runner_node_labels
  node_taints = var.runner_node_taints

  tags = var.tags
}

# ------------------ ACR Pull Permission for AKS ------------------

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
