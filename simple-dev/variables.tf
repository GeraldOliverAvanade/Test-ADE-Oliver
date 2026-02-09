variable "envName" {
  description = "Environment name used as a prefix for resources"
  type        = string
}

variable "location" {
  description = "Azure region for deployment (optional). If empty, uses resource group location."
  type        = string
  default     = ""
}

# ADE usually supplies RG info; often you map it into this variable.
variable "resource_group_name" {
  description = "Resource group name to deploy into"
  type        = string
}
