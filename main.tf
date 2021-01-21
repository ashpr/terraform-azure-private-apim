locals {
  publisher_name = "Name"
  publisher_email = "Email!"
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_group_name}-vnet"
  address_space       = ["10.100.0.0/16"]
  location            = var.primary_location
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_subnet" "apim" {
  name                      = "apim"
  address_prefixes            = ["10.100.0.0/28"]
  resource_group_name       = data.azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.main.name
}

resource "azurerm_api_management" "main" {
  name                 = "${data.azurerm_resource_group.main.name}"
  location             = var.primary_location
  resource_group_name  = data.azurerm_resource_group.main.name
  publisher_name       = local.publisher_name
  publisher_email      = local.publisher_email
  virtual_network_type = "Internal"

  sign_up {
    enabled = false
    terms_of_service {
      consent_required = false
      enabled = false
      text = "TBD"
    }
  }

  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  sku_name = "Developer_1"

  dynamic "additional_location" {
    for_each = toset(var.secondary_locations)

    content {
      location = additional_location.value
    }
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      hostname_configuration
    ]
  }
}

resource "azurerm_network_security_group" "main" {
  name                = "apim"
  location            = azurerm_api_management.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "AzureActiveDirectory"
    destination_port_ranges    = ["443", "80"]
    direction                  = "Outbound"
    name                       = "AllowAzureActiveDirectoryOutBound"
    priority                   = 100
    protocol                   = "TCP"
    source_address_prefix      = "VirtualNetwork"
    source_port_range          = "*"
  }

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "VirtualNetwork"
    destination_port_ranges    = ["443", "80"]
    direction                  = "Inbound"
    name                       = "AllowClientCommunicationToApiInBound"
    priority                   = 100
    protocol                   = "TCP"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "VirtualNetwork"
    destination_port_range     = "3443"
    direction                  = "Inbound"
    name                       = "AllowApiManagementInBound"
    priority                   = 110
    protocol                   = "TCP"
    source_address_prefix      = "ApiManagement"
    source_port_range          = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.main.id
}
