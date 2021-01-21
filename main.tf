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

terraform {
  backend "azurerm" {
  }
}

provider "azurerm" {
  version                    = "=2.41.0"
  skip_provider_registration = "true"
  features {}
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_key_vault" "api" {
  name                = var.custom_domain_certificate.key_vault_name
  resource_group_name = var.custom_domain_certificate.key_vault_resource_group_name
}

data "azurerm_key_vault" "portal" {
  name                = var.portal_custom_domain_certificate.key_vault_name
  resource_group_name = var.portal_custom_domain_certificate.key_vault_resource_group_name
}

data "azurerm_key_vault" "management" {
  name                = var.management_custom_domain_certificate.key_vault_name
  resource_group_name = var.management_custom_domain_certificate.key_vault_resource_group_name
}

data "azurerm_key_vault_secret" "api-cert" {
  name         = var.custom_domain_certificate.certificate_name
  key_vault_id = data.azurerm_key_vault.api.id
}

data "azurerm_key_vault_secret" "portal-cert" {
  name         = var.portal_custom_domain_certificate.certificate_name
  key_vault_id = data.azurerm_key_vault.portal.id
}

data "azurerm_key_vault_secret" "apim-cert" {
  name         = var.management_custom_domain_certificate.certificate_name
  key_vault_id = data.azurerm_key_vault.management.id
}

resource "azurerm_key_vault_access_policy" "read_api_certificates" {
  key_vault_id = data.azurerm_key_vault.api.id
  tenant_id    = azurerm_api_management.main.identity[0].tenant_id
  object_id    =.azurerm_api_management.main.identity[0].principal_id

  secret_permissions = [
    "get",
  ]

  certificate_permissions = [
    "get",
  ]
}

resource "azurerm_api_management_custom_domain" "main" {
  api_management_id = azurerm_api_management.main.id

  # Default
  # proxy {
  #   default_ssl_binding          = false
  #   host_name                    = "ap-apim.azure-api.net"
  #   negotiate_client_certificate = false
  # }

  proxy {
    host_name = trim(azurerm_dns_cname_record.api.fqdn, ".")
    key_vault_id = data.azurerm_key_vault_secret.api-cert.id
  }

  developer_portal {
    host_name = trim(azurerm_dns_cname_record.portal.fqdn, ".")
    key_vault_id = data.azurerm_key_vault_secret.portal-cert.id
  }

  management {
    host_name = trim(azurerm_dns_cname_record.apim.fqdn, ".")
    key_vault_id = data.azurerm_key_vault_secret.apim-cert.id
  }

  depends_on = [
    azurerm_key_vault_access_policy.read_api_certificates
  ]
}

resource "azurerm_private_dns_zone" "main" {
  name                = var.dns_zone.name
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  name                  = "private-dns-zone-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  virtual_network_id    = azurerm_virtual_network.main.id
  resource_group_name = data.azurerm_resource_group.main.name
}

resource "azurerm_private_dns_a_record" "portal" {
  name                = "portal"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 300
  records             = [
    data.azurerm_api_management.main.private_ip_addresses.0
  ]
}

resource "azurerm_private_dns_a_record" "api" {
  name                = "api"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 300
  records             = [
    data.azurerm_api_management.main.private_ip_addresses.0
  ]
}

resource "azurerm_private_dns_a_record" "apim" {
  name                = "apim"
  zone_name           = azurerm_private_dns_zone.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  ttl                 = 300
  records             = [
    data.azurerm_api_management.main.private_ip_addresses.0
  ]
}

resource "azurerm_user_assigned_identity" "gateway" {
  resource_group_name = data.azurerm_resource_group.main.name
  location = azurerm_api_management.main.location

  name = "gateway-${data.azurerm_api_management.main.location}"
}

resource "azurerm_key_vault_access_policy" "gateway" {
  key_vault_id = data.azurerm_key_vault.api.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.gateway.principal_id

  secret_permissions = [
    "get",
  ]

  certificate_permissions = [
    "get",
  ]
}

resource "azurerm_application_gateway" "main" {
  name = "${var.resource_group_name}-ag"
  location =.azurerm_api_management.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  identity {
    type = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.gateway.id]
  }

  autoscale_configuration {
    max_capacity = 2
    min_capacity = 0
  }

  frontend_port {
    name = "port_443"
    port = 443
  }

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
    capacity = 0
  }

  frontend_ip_configuration {
    name                          = "appGwPublicFrontendIp"
    public_ip_address_id          = azurerm_public_ip.main.id
    private_ip_address_allocation = "Dynamic"
  }

  backend_http_settings {
    cookie_based_affinity               = "Disabled"
    name                                = "api-settings"
    port                                = 443
    protocol                            = "Https"
    pick_host_name_from_backend_address = true
    request_timeout                     = 20
    probe_name                          = "api-probe"
  }

  backend_http_settings {
    cookie_based_affinity               = "Disabled"
    name                                = "portal-settings"
    port                                = 443
    protocol                            = "Https"
    pick_host_name_from_backend_address = true
    request_timeout                     = 20
    probe_name                          = "portal-probe"
  }

  backend_http_settings {
    cookie_based_affinity               = "Disabled"
    name                                = "apim-settings"
    port                                = 443
    protocol                            = "Https"
    pick_host_name_from_backend_address = true
    request_timeout                     = 20
    probe_name                          = "apim-probe"
  }

  probe {
    interval                                  = 30
    name                                      = "api-probe"
    path                                      = "/status-0123456789abcdef"
    protocol                                  = "Https"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      body = ""
      status_code = [
        "200-399"
      ]
    }
  }

  probe {
    interval                                  = 30
    name                                      = "portal-probe"
    path                                      = "/internal-status-0123456789abcdef"
    protocol                                  = "Https"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      body = ""
      status_code = [
        "200-399"
      ]
    }
  }

  probe {
    interval                                  = 30
    name                                      = "apim-probe"
    path                                      = "/ServiceStatus"
    protocol                                  = "Https"
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      body = ""
      status_code = [
        "200-399"
      ]
    }
  }

  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = azurerm_subnet.gateway.id
  }

  backend_address_pool {
    name      = "portal-pool"
    fqdns = [
       trim(azurerm_private_dns_a_record.portal.fqdn, ".")
    ]
  }

  backend_address_pool {
    name      = "api-pool"
    fqdns = [
       trim(azurerm_private_dns_a_record.api.fqdn, ".")
    ]
  }

  backend_address_pool {
    name      = "apim-pool"
    fqdns = [
       trim(azurerm_private_dns_a_record.apim.fqdn, ".")
    ]
  }

  http_listener {
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "port_443"
    name                           = "api"
    protocol                       = "Https"
    require_sni                    = false
    ssl_certificate_name           = "api-certificate"
    host_name                      = trim(azurerm_dns_cname_record.api.fqdn, ".")
  }

  http_listener {
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "port_443"
    name                           = "portal"
    protocol                       = "Https"
    require_sni                    = false
    ssl_certificate_name           = "portal-certificate"
    host_name                      = trim(azurerm_dns_cname_record.portal.fqdn, ".")
  }

  http_listener {
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "port_443"
    name                           = "apim"
    protocol                       = "Https"
    require_sni                    = false
    ssl_certificate_name           = "apim-certificate"
    host_name                      = trim(azurerm_dns_cname_record.apim.fqdn, ".")
  }

  ssl_certificate {
    name     = "api-certificate"
    key_vault_secret_id = data.azurerm_key_vault_secret.api-cert.id
  }

  ssl_certificate {
    name     = "portal-certificate"
    key_vault_secret_id = data.azurerm_key_vault_secret.portal-cert.id
  }

  ssl_certificate {
    name     = "apim-certificate"
    key_vault_secret_id = data.azurerm_key_vault_secret.apim-cert.id
  }

  request_routing_rule {
    http_listener_name         = "api"
    name                       = "api"
    rule_type                  = "Basic"
    backend_address_pool_name  = "api-pool"
    backend_http_settings_name = "api-settings"
  }

  request_routing_rule {
    http_listener_name         = "portal"
    name                       = "portal"
    rule_type                  = "Basic"
    backend_address_pool_name  = "portal-pool"
    backend_http_settings_name = "portal-settings"
  }

  request_routing_rule {
    http_listener_name         = "apim"
    name                       = "apim"
    rule_type                  = "Basic"
    backend_address_pool_name  = "apim-pool"
    backend_http_settings_name = "apim-settings"
  }

  depends_on = [ 
    azurerm_key_vault_access_policy.gateway
  ]
}

resource "azurerm_public_ip" "main" {
  name                = "${data.azurerm_resource_group.main.name}-ip"
  sku                 = "Standard"
  allocation_method   = "Static"
  domain_name_label   = "${data.azurerm_resource_group.main.name}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = azurerm_api_management.main.location
  zones               = []
}

resource "azurerm_network_security_group" "gateway" {
  name                = "gateway"
  location            = azurerm_api_management.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "*"
    destination_port_range     = "65200-65535"
    direction                  = "Inbound"
    name                       = "AllowBackendHealthPortsInBound"
    priority                   = 100
    protocol                   = "TCP"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "*"
    destination_port_range     = "443"
    direction                  = "Inbound"
    name                       = "AllowApiManagerHttpsInBound"
    priority                   = 110
    protocol                   = "TCP"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }
}

resource "azurerm_subnet" "gateway" {
  address_prefixes            = ["10.100.0.128/27"]
  virtual_network_name      = data.azurerm_virtual_network.main.name
  name                      = "application-gateway"
  resource_group_name     = data.azurerm_virtual_network.main.resource_group_name
}

resource "azurerm_subnet_network_security_group_association" "gateway" {
  subnet_id                 = azurerm_subnet.gateway.id
  network_security_group_id = azurerm_network_security_group.gateway.id
}

resource "azurerm_dns_cname_record" "api" {
  name                = "api"
  zone_name           = var.dns_zone.name
  resource_group_name = var.dns_zone.resource_group_name
  ttl                 = 300
  record              = azurerm_public_ip.main.fqdn
}

resource "azurerm_dns_cname_record" "portal" {
  name                = "portal"
  zone_name           = var.dns_zone.name
  resource_group_name = var.dns_zone.resource_group_name
  ttl                 = 300
  record              = azurerm_public_ip.main.fqdn
}

resource "azurerm_dns_cname_record" "apim" {
  name                = "apim"
  zone_name           = var.dns_zone.name
  resource_group_name = var.dns_zone.resource_group_name
  ttl                 = 300
  record              = azurerm_public_ip.main.fqdn
}
