data "azurerm_client_config" "current" {
}

locals {
  domain = "${var.environment}-${var.application}"

  tags = {
    application = var.application
    environment = var.environment
    deployment  = "terraform"
  }
}

# ======================================================================================
# Resource Group
# ======================================================================================

resource "azurerm_resource_group" "app_resource_group" {
  location = var.location
  name     = local.domain
  tags     = local.tags
}

# ======================================================================================
# Service Plan
# ======================================================================================

resource "azurerm_app_service_plan" "app_service_plan" {
  name     = "${local.domain}-app-service-plan"
  location = azurerm_resource_group.app_resource_group.location
  domain   = azurerm_resource_group.app_resource_group.name

  sku {
    tier = "Free"
    size = "F1"
  }

  tags = local.tags
}

# ======================================================================================
# App Service
# ======================================================================================

resource "azurerm_app_service" "app_service" {
  name                = "${local.domain}-app-service"
  location            = azurerm_resource_group.app_resource_group.location
  domain              = azurerm_resource_group.app_resource_group.name
  app_service_plan_id = azurerm_app_service_plan.app_service_plan.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# ======================================================================================
# KeyVault
# ======================================================================================

resource "azurerm_key_vault" "key_vault" {
  name                        = "${local.domain}-keyvault"
  location                    = azurerm_resource_group.app_resource_group.location
  domain                      = azurerm_resource_group.app_resource_group.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  enabled_for_disk_encryption = true

  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.service_principal_object_id

    key_permissions = [
      "get",
      "list",
      "create",
      "delete",
    ]

    secret_permissions = [
      "get",
      "list",
      "set",
      "delete",
    ]
  }

  tags = local.tags
}

resource "azurerm_key_vault_access_policy" "key_vault_access_policy_app_service" {
  key_vault_id = azurerm_key_vault.key_vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_app_service.app_service.identity[0].principal_id

  key_permissions = [
    "get",
    "list",
    "delete",
  ]

  secret_permissions = [
    "get",
    "list",
    "delete",
  ]
}

# ======================================================================================
# Azure SQL Server & Database
# ======================================================================================

resource "azurerm_sql_server" "sql_server" {
  name                         = "${local.domain}-sqlserver"
  location                     = azurerm_resource_group.app_resource_group.location
  domain                       = azurerm_resource_group.app_resource_group.name
  version                      = "12.0"
  administrator_login          = var.sql_server_login
  administrator_login_password = var.sql_server_password
  tags                         = local.tags
}

resource "azurerm_sql_database" "sql_database" {
  name        = "${local.domain}-db"
  domain      = azurerm_resource_group.app_resource_group.name
  location    = azurerm_resource_group.app_resource_group.location
  server_name = azurerm_sql_server.sql_server.name
  tags        = local.tags
}

resource "azurerm_key_vault_secret" "key_vault_secret_connectionstring" {
  name         = "ConnectionString--Default"
  value        = "Server=tcp:${azurerm_sql_server.sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_sql_database.sql_database.name};Persist Security Info=False;User ID=${azurerm_sql_server.sql_server.administrator_login};Password=${azurerm_sql_server.sql_server.administrator_login_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = azurerm_key_vault.key_vault.id
  tags         = local.tags
}

resource "azurerm_sql_firewall_rule" "sql_firewall_rule_allow_access_to_azure_services" {
  name              = "${local.domain}-firewall-rule-allow-access-to-azure-services"
  domain            = azurerm_resource_group.app_resource_group.name
  server_name       = azurerm_sql_server.sql_server.name
  start_ip_address  = "0.0.0.0"
  end_ip_address    = "0.0.0.0"
}
