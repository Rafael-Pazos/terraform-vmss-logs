output "vmss_public_ip_fqdn" {
   value = azurerm_public_ip.vmss.fqdn
}

output "jumpbox_public_ip_fqdn" {
   value = azurerm_public_ip.jumpbox.fqdn
}

output "jumpbox_public_ip" {
   value = azurerm_public_ip.jumpbox.ip_address
}

output "testvm_public_ip_fqdn" {
   value = azurerm_public_ip.testvm.fqdn
}

output "testvm_public_ip" {
   value = azurerm_public_ip.testvm.ip_address
}

output "instrumentation_key" {
  value = azurerm_application_insights.vmss.instrumentation_key
}

output "app_id" {
  value = azurerm_application_insights.vmss.app_id
}