variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
}

variable "primary_location" {
  description = "Primary Location"
  type        = string
  default     = "uksouth"
}

variable "secondary_locations" {
  description = "Secondary locations"
  type        = list(string)
  default     = []
}

variable "custom_domain_certificate" {
  description = "HTTPS Certificate for APIM Custom Domain"
  type = object({
    certificate_name = string
    key_vault_name = string
    key_vault_resource_group_name = string
  })
}

variable "portal_custom_domain_certificate" {
  description = "HTTPS Certificate for APIM Portal Custom Domain"
  type = object({
    certificate_name = string
    key_vault_name = string
    key_vault_resource_group_name = string
  })
}

variable "management_custom_domain_certificate" {
  description = "HTTPS Certificate for APIM Management Custom Domain"
  type = object({
    certificate_name = string
    key_vault_name = string
    key_vault_resource_group_name = string
  })
}

variable "dns_zone" {
  type = object({
      name = string
      resource_group_name = string
  })
}
