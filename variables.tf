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
