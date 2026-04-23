output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "resource_group_name" {
  description = "Azure resource group name"
  value       = azurerm_resource_group.main.name
}

output "dns_zone_name" {
  description = "Azure DNS zone name"
  value       = azurerm_dns_zone.main.name
}

output "dns_ns_records" {
  description = "NS records to add at your registrar to delegate the DNS zone"
  value       = azurerm_dns_zone.main.name_servers
}

output "kibana_url" {
  description = "Kibana URL"
  value       = "https://kibana.${var.dns_zone_name}"
}


output "kubeconfig_command" {
  description = "Command to merge AKS credentials into ~/.kube/config"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}
