# =============================================================================
# Outputs
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_get_credentials_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "acr_login_server" {
  description = "ACR login server URL"
  value       = azurerm_container_registry.acr.login_server
}

output "runner_image" {
  description = "Full image reference for the custom runner"
  value       = local.runner_image
}

output "github_workflow_runs_on" {
  description = "Use this label in your GitHub workflow 'runs-on' field"
  value       = var.runner_scale_set_name
}

output "runner_image_note" {
  description = "The custom runner image is built and pushed automatically via az acr build"
  value       = "Image ${local.runner_image} is built automatically during terraform apply (rebuilds when Dockerfile changes)"
}
