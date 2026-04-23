resource "azurerm_storage_account" "snapshots" {
  name                     = "${replace(var.prefix, "-", "")}snapshots"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_container" "snapshots" {
  name                  = "elasticsearch-snapshots"
  storage_account_name  = azurerm_storage_account.snapshots.name
  container_access_type = "private"
}

resource "null_resource" "elasticsearch_snapshot_secret" {
  triggers = {
    storage_account = azurerm_storage_account.snapshots.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl create secret generic elasticsearch-snapshot-credentials \
        --namespace=elastic-system \
        --from-literal=azure.client.default.account='${azurerm_storage_account.snapshots.name}' \
        --from-literal=azure.client.default.key='${azurerm_storage_account.snapshots.primary_access_key}' \
        --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }

  depends_on = [null_resource.wait_for_eck_operator]
}
