terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "example" {
  name     = "rg-terraform-test"
  location = "eastus"


  tags = {
    CREATED_BY = "abhishgu"
  }
}

resource "azurerm_storage_account" "synapse" {
  name                     = "kehsihbasynapsestorage"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = "true"
}

data "azurerm_client_config" "example" {
}

resource "azurerm_role_assignment" "example" {
  scope                = azurerm_storage_account.synapse.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.example.object_id
}

resource "azurerm_storage_data_lake_gen2_filesystem" "example" {
  name               = "synapseadlsfs"
  storage_account_id = azurerm_storage_account.synapse.id

  depends_on = [azurerm_role_assignment.example]
}

resource "azurerm_synapse_workspace" "example" {
  name                                 = "kehsihbasynapsewrkspace"
  resource_group_name                  = azurerm_resource_group.example.name
  location                             = azurerm_resource_group.example.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.example.id
  sql_administrator_login              = "sqladmin"
  sql_administrator_login_password     = "P@ssw0rd123"
}

resource "azurerm_synapse_firewall_rule" "example" {
  
  name                 = "AllowAll"
  synapse_workspace_id = azurerm_synapse_workspace.example.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "255.255.255.255"
}

resource "azurerm_synapse_spark_pool" "example" {
  name                 = "sparkling"
  synapse_workspace_id = azurerm_synapse_workspace.example.id
  node_size_family     = "MemoryOptimized"
  node_size            = "Small"

  auto_scale {
    max_node_count = 50
    min_node_count = 3
  }

  auto_pause {
    delay_in_minutes = 15
  }
}

resource "azurerm_storage_account" "sqldb" {
  name                     = "kehsihbasqlserverstorage"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_mssql_server" "example" {
  name                         = "kehsihba-sqlserver"
  resource_group_name          = azurerm_resource_group.example.name
  location                     = azurerm_resource_group.example.location
  version                      = "12.0"
  administrator_login          = "sqlserveradmin"
  administrator_login_password = "P@ssw0rd123"
}

resource "azurerm_mssql_firewall_rule" "example" {
  name             = "AllowAzureAccess"
  server_id        = azurerm_mssql_server.example.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "example" {
  name           = "kehsihba-sqlserver-db"
  server_id      = azurerm_mssql_server.example.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  license_type   = "LicenseIncluded"
  max_size_gb    = 4
  read_scale     = true
  sku_name       = "BC_Gen5_2"
  zone_redundant = true
  sample_name = "AdventureWorksLT"
}

resource "azurerm_mssql_database_extended_auditing_policy" "example" {
  database_id                             = azurerm_mssql_database.example.id
  storage_endpoint                        = azurerm_storage_account.sqldb.primary_blob_endpoint
  storage_account_access_key              = azurerm_storage_account.sqldb.primary_access_key
  storage_account_access_key_is_secondary = false
  retention_in_days                       = 6
}

resource "azurerm_key_vault" "example" {
  name                       = "kehsihbaazkeyvault1"
  location                   = azurerm_resource_group.example.location
  resource_group_name        = azurerm_resource_group.example.name
  tenant_id                  = data.azurerm_client_config.example.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.example.tenant_id
    object_id = data.azurerm_client_config.example.object_id

    secret_permissions = [
      "set",
      "get",
      "delete",
      "purge",
      "recover",
      "list"
    ]
  }

  access_policy {
    tenant_id = azurerm_synapse_workspace.example.identity[0].tenant_id
    object_id = azurerm_synapse_workspace.example.identity[0].principal_id

    secret_permissions = [
      "get"
    ]
  }
}

resource "azurerm_key_vault_secret" "example" {
  name         = "azsqldb-connection-string"
  value        = "jdbc:sqlserver://${azurerm_mssql_server.example.name}.database.windows.net:1433;database=${azurerm_mssql_database.example.name};user=${azurerm_mssql_server.example.administrator_login}@${azurerm_mssql_server.example.name};password=${azurerm_mssql_server.example.administrator_login_password};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
  key_vault_id = azurerm_key_vault.example.id
}