# a connection monitor
resource "azurerm_network_connection_monitor" "jumpbox" {
  name                         = "jumpbox-internet-Monitor"
  network_watcher_id           ="/subscriptions/95b44dd6-5808-485e-9f1a-923eaeef3b37/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_westeurope"
  #network_watcher_id           = azurerm_network_watcher.vmss.id
  location                     = var.location
  
  endpoint {
    name               = "jumpbox"
    target_resource_id = azurerm_virtual_machine.jumpbox.id
  }

  endpoint {
    name    = "destination"
    address = "terraform.io"
  }

  test_configuration {
    name                      = "tcpName"
    protocol                  = "Tcp"
    test_frequency_in_seconds = 60

    tcp_configuration {
      port = 80
    }
  }

  test_group {
    name                     = "exampletg"
    destination_endpoints    = ["destination"]
    source_endpoints         = ["jumpbox"]
    test_configuration_names = ["tcpName"]
  }

  notes = "examplenote"

  output_workspace_resource_ids = [azurerm_log_analytics_workspace.vmss.id]

  depends_on = [azurerm_virtual_machine_extension.testvmnet]
}

# second connection monitor
resource "azurerm_network_connection_monitor" "jumpbox-test" {
  name                         = "jumpbox-test-Monitor"
  network_watcher_id           ="/subscriptions/95b44dd6-5808-485e-9f1a-923eaeef3b37/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_westeurope"
  location                     = var.location
 
  endpoint {
    name                       = "jumpbox"
    target_resource_id         = azurerm_virtual_machine.jumpbox.id
    target_resource_type       = "AzureVM"
  }
  endpoint {
    name                       = "testvm"
    target_resource_id         = azurerm_virtual_machine.testvm.id
    target_resource_type       = "AzureVM"
  }
  test_configuration {
    name                      = "tcpName"
    protocol                  = "Tcp"
    test_frequency_in_seconds = 60
    tcp_configuration {
      port = 80
    }
  }
  test_configuration {
    name                      = "ping"
    protocol                  = "Icmp"
    test_frequency_in_seconds = 60
    icmp_configuration {
      trace_route_enabled = true
    }
  }
  test_group {
    name                     = "jumpbox-test"
    destination_endpoints    = ["testvm"]
    source_endpoints         = ["jumpbox"]
    test_configuration_names = ["tcpName", "ping"]
  }
  notes = "examplenote"

  output_workspace_resource_ids = [azurerm_log_analytics_workspace.vmss.id]
  depends_on = [azurerm_virtual_machine_extension.testvmnet]
}