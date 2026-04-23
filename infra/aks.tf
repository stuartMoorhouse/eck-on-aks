resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.prefix
  tags                = var.tags

  default_node_pool {
    name                = "default"
    min_count           = 1
    max_count           = var.aks_node_count
    vm_size             = var.aks_node_sku
    enable_auto_scaling = true
  }

  oidc_issuer_enabled = true

  identity {
    type = "SystemAssigned"
  }

  web_app_routing {
    dns_zone_id = azurerm_dns_zone.main.id
  }
}


resource "null_resource" "aks_credentials" {
  triggers = {
    cluster_id = azurerm_kubernetes_cluster.main.id
  }

  provisioner "local-exec" {
    command = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
  }
}
