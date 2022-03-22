terraform {
  required_version = ">=0.12"
   
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

resource "azurerm_resource_group" "vmss" {
 name     = var.resource_group_name
 location = var.location
 tags     = var.tags
}

resource "random_string" "fqdn" {
 length  = 6
 special = false
 upper   = false
 number  = false
}

resource "azurerm_log_analytics_workspace" "vmss" {
  name                = "vmss-laws"
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "vmss" {
  name                = "vmss-appinsights"
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name
  workspace_id        = azurerm_log_analytics_workspace.vmss.id
  application_type    = "other"
}

resource "azurerm_security_center_workspace" "vmss" {
  scope        = "/subscriptions/95b44dd6-5808-485e-9f1a-923eaeef3b37"
  workspace_id = azurerm_log_analytics_workspace.vmss.id
}

resource "azurerm_virtual_network" "vmss" {
 name                = "vmss-vnet"
 address_space       = ["10.0.0.0/16"]
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
 tags                = var.tags
}

resource "azurerm_subnet" "vmss" {
 name                 = "vmss-subnet"
 resource_group_name  = azurerm_resource_group.vmss.name
 virtual_network_name = azurerm_virtual_network.vmss.name
 address_prefixes       = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "vmss" {
  name                = "vmss-subnet-nsg"
  location            = azurerm_resource_group.vmss.location
  resource_group_name = azurerm_resource_group.vmss.name
}

# VMSS
resource "azurerm_subnet_network_security_group_association" "vmss" {
  subnet_id                 = azurerm_subnet.vmss.id
  network_security_group_id = azurerm_network_security_group.vmss.id
}

resource "azurerm_public_ip" "vmss" {
 name                         = "vmss-public-ip"
 location                     = var.location
 resource_group_name          = azurerm_resource_group.vmss.name
 allocation_method            = "Static"
 domain_name_label            = random_string.fqdn.result
 tags                         = var.tags
}

resource "azurerm_lb" "vmss" {
 name                = "vmss-lb"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
 frontend_ip_configuration {
   name                 = "PublicIPAddress"
   public_ip_address_id = azurerm_public_ip.vmss.id
 }
 tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "bpepool" {
 loadbalancer_id     = azurerm_lb.vmss.id
 name                = "BackEndAddressPool"
}

resource "azurerm_lb_probe" "vmss" {
 resource_group_name = azurerm_resource_group.vmss.name
 loadbalancer_id     = azurerm_lb.vmss.id
 name                = "ssh-running-probe"
 port                = var.application_port
}

resource "azurerm_lb_rule" "lbnatrule" {
   resource_group_name            = azurerm_resource_group.vmss.name
   loadbalancer_id                = azurerm_lb.vmss.id
   name                           = "http"
   protocol                       = "Tcp"
   frontend_port                  = var.application_port
   backend_port                   = var.application_port
   backend_address_pool_ids       = [azurerm_lb_backend_address_pool.bpepool.id]
   frontend_ip_configuration_name = "PublicIPAddress"
   probe_id                       = azurerm_lb_probe.vmss.id
}

resource "azurerm_virtual_machine_scale_set" "vmss" {
 name                = "vmscaleset"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
 upgrade_policy_mode = "Automatic"
 sku {
   name     = "Standard_DS1_v2"
   tier     = "Standard"
   capacity = 2
 }
 storage_profile_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }
 storage_profile_os_disk {
   name              = ""
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }
 storage_profile_data_disk {
   lun          = 0
   caching        = "ReadWrite"
   create_option  = "Empty"
   disk_size_gb   = 10
 }
 os_profile {
   computer_name_prefix = "vmlab"
   admin_username       = var.admin_user
   admin_password       = var.admin_password
 }
 os_profile_linux_config {
   disable_password_authentication = false
 }
 network_profile {
   name    = "terraformnetworkprofile"
   primary = true
   ip_configuration {
     name                                   = "IPConfiguration"
     subnet_id                              = azurerm_subnet.vmss.id
     load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.bpepool.id]
     primary = true
   }
 }
 tags = var.tags
}

resource "azurerm_virtual_machine_scale_set_extension" "bash-ext-vmss" {
 name                         = "bash-ext-vmss"
 virtual_machine_scale_set_id = azurerm_virtual_machine_scale_set.vmss.id
 publisher                    = "Microsoft.Azure.Extensions"
 type                         = "CustomScript"
 type_handler_version         = "2.1"
 protected_settings = <<PROTECTED_SETTINGS
    {
      "commandToExecute": "sudo apt-get update && sudo apt-get -y install unzip && sudo apt-get -y install stress-ng"
    }
 PROTECTED_SETTINGS 
}

resource "azurerm_virtual_machine_scale_set_extension" "vmss" {
  name                 = "LoganalyticsAgent"
  virtual_machine_scale_set_id = azurerm_virtual_machine_scale_set.vmss.id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "OmsAgentForLinux"
  type_handler_version = "1.13"
  auto_upgrade_minor_version = true
  settings = jsonencode(
    {
      "workspaceId": azurerm_log_analytics_workspace.vmss.workspace_id,
      "stopOnMultipleConnections": "true"
    }
  )
  protected_settings = jsonencode(
    {
      "workspaceKey" : azurerm_log_analytics_workspace.vmss.primary_shared_key
    }
  )
}

resource "azurerm_virtual_machine_scale_set_extension" "vmssdep" {
  name                 = "DependencysAgent"
  virtual_machine_scale_set_id = azurerm_virtual_machine_scale_set.vmss.id
  publisher            = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                 = "DependencyAgentLinux"
  type_handler_version = "9.5"
  auto_upgrade_minor_version = true
}

# jumpbox VM for testing purposes
resource "azurerm_public_ip" "jumpbox" {
 name                         = "jumpbox-public-ip"
 location                     = var.location
 resource_group_name          = azurerm_resource_group.vmss.name
 allocation_method            = "Static"
 domain_name_label            = "${random_string.fqdn.result}-ssh"
 tags                         = var.tags
}

resource "azurerm_network_interface" "jumpbox" {
 name                = "jumpbox-nic"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
 ip_configuration {
   name                          = "IPConfiguration"
   subnet_id                     = azurerm_subnet.vmss.id
   private_ip_address_allocation = "dynamic"
   public_ip_address_id          = azurerm_public_ip.jumpbox.id
 }
 tags = var.tags
}

resource "azurerm_virtual_machine" "jumpbox" {
 name                  = "jumpbox"
 location              = var.location
 resource_group_name   = azurerm_resource_group.vmss.name
 network_interface_ids = [azurerm_network_interface.jumpbox.id]
 vm_size               = "Standard_DS1_v2"
 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }
 storage_os_disk {
   name              = "jumpbox-osdisk"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }
 os_profile {
   computer_name  = "jumpbox"
   admin_username = var.admin_user
   admin_password = var.admin_password
 }
 os_profile_linux_config {
   disable_password_authentication = false
 }
 tags = var.tags
}

resource "azurerm_virtual_machine_extension" "bash-ext-jumpbox" {
 name                         = "bash-ext-jumpbox"
 virtual_machine_id           = azurerm_virtual_machine.jumpbox.id
 publisher                    = "Microsoft.Azure.Extensions"
 type                         = "CustomScript"
 type_handler_version         = "2.1"
 protected_settings = <<PROTECTED_SETTINGS
    {
      "commandToExecute": "sudo apt-get update && sudo apt-get -y install unzip && sudo apt-get -y install stress-ng"
    }
 PROTECTED_SETTINGS 
}
resource "azurerm_virtual_machine_extension" "jumpbox" {
  name                 = "LoganalyticsAgent"
  virtual_machine_id   = azurerm_virtual_machine.jumpbox.id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "OmsAgentForLinux"
  type_handler_version = "1.13"
  settings = jsonencode(
    {
      "workspaceId": azurerm_log_analytics_workspace.vmss.workspace_id
    }
  )
  protected_settings = jsonencode(
    {
      "workspaceKey" : azurerm_log_analytics_workspace.vmss.primary_shared_key
    }
  )
}

resource "azurerm_virtual_machine_extension" "jumpboxdep" {
  name                 = "DependencysAgent"
  virtual_machine_id   = azurerm_virtual_machine.jumpbox.id
  publisher            = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                 = "DependencyAgentLinux"
  type_handler_version = "9.5"
  auto_upgrade_minor_version = true
}  

resource "azurerm_virtual_machine_extension" "jumpboxnet" {
  name                 = "NetworkWatcherAgent"
  virtual_machine_id = azurerm_virtual_machine.jumpbox.id
  publisher            = "Microsoft.Azure.NetworkWatcher"
  type                 = "NetworkWatcherAgentLinux"
  type_handler_version = "1.4"
  auto_upgrade_minor_version = true
}

#second VM for testing purposes

resource "azurerm_public_ip" "testvm" {
 name                         = "testvm-public-ip"
 location                     = var.location
 resource_group_name          = azurerm_resource_group.vmss.name
 allocation_method            = "Static"
 domain_name_label            = "${random_string.fqdn.result}-http"
 tags                         = var.tags
}

resource "azurerm_network_interface" "testvm" {
 name                = "testvm-nic"
 location            = var.location
 resource_group_name = azurerm_resource_group.vmss.name
 ip_configuration {
   name                          = "IPConfiguration"
   subnet_id                     = azurerm_subnet.vmss.id
   private_ip_address_allocation = "dynamic"
   public_ip_address_id          = azurerm_public_ip.testvm.id
 }
 tags = var.tags
}
resource "azurerm_virtual_machine" "testvm" {
 name                  = "testvm"
 location              = var.location
 resource_group_name   = azurerm_resource_group.vmss.name
 network_interface_ids = [azurerm_network_interface.testvm.id]
 vm_size               = "Standard_DS1_v2"
 storage_image_reference {
   publisher = "Canonical"
   offer     = "UbuntuServer"
   sku       = "16.04-LTS"
   version   = "latest"
 }
 storage_os_disk {
   name              = "testvm-osdisk"
   caching           = "ReadWrite"
   create_option     = "FromImage"
   managed_disk_type = "Standard_LRS"
 }
 os_profile {
   computer_name  = "testvm"
   admin_username = var.admin_user
   admin_password = var.admin_password
 }
 os_profile_linux_config {
   disable_password_authentication = false
 }
 tags = var.tags
}

resource "azurerm_virtual_machine_extension" "bash-ext-testvm" {
 name                         = "bash-ext-testvm"
 virtual_machine_id           = azurerm_virtual_machine.testvm.id
 publisher                    = "Microsoft.Azure.Extensions"
 type                         = "CustomScript"
 type_handler_version         = "2.1"
 protected_settings = <<PROTECTED_SETTINGS
    {
      "commandToExecute": "sudo apt-get update && sudo apt-get -y install unzip && sudo apt-get -y install stress-ng"
    }
 PROTECTED_SETTINGS 
}
resource "azurerm_virtual_machine_extension" "testvm" {
  name                 = "LoganalyticsAgent"
  virtual_machine_id   = azurerm_virtual_machine.testvm.id
  publisher            = "Microsoft.EnterpriseCloud.Monitoring"
  type                 = "OmsAgentForLinux"
  type_handler_version = "1.13"
  settings = jsonencode(
    {
      "workspaceId": azurerm_log_analytics_workspace.vmss.workspace_id
    }
  )
  protected_settings = jsonencode(
    {
      "workspaceKey" : azurerm_log_analytics_workspace.vmss.primary_shared_key
    }
  )
}

resource "azurerm_virtual_machine_extension" "testvmdep" {
  name                 = "DependencysAgent"
  virtual_machine_id   = azurerm_virtual_machine.testvm.id
  publisher            = "Microsoft.Azure.Monitoring.DependencyAgent"
  type                 = "DependencyAgentLinux"
  type_handler_version = "9.5"
  auto_upgrade_minor_version = true
}  

resource "azurerm_virtual_machine_extension" "testvmnet" {
  name                 = "NetworkWatcherAgent"
  virtual_machine_id = azurerm_virtual_machine.testvm.id
  publisher            = "Microsoft.Azure.NetworkWatcher"
  type                 = "NetworkWatcherAgentLinux"
  type_handler_version = "1.4"
  auto_upgrade_minor_version = true
}

# identity for chaos studio
resource "azurerm_user_assigned_identity" "chaos-studio" {
  location                     = var.location
  resource_group_name          = azurerm_resource_group.vmss.name
  name = "chaos-studio-user"
}

# the network watcher
#resource "azurerm_network_watcher" "vmss" {
#  name                         = "vmss-Watcher"
#  location                     = var.location
#  resource_group_name          = azurerm_resource_group.vmss.name
#}

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
