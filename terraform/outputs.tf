output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "app_service_hostname" {
  value = azurerm_app_service.app_service.default_site_hostname
}

output "key_vault_uri" {
  value = azurerm_key_vault.key_vault.vault_uri
}

