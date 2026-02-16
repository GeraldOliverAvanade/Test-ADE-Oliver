terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# =========
# Variables
# =========
variable "resource_group_name" {
  type        = string
  description = "Resource group name where AI Services will be created"
}

variable "location" {
  type        = string
  description = "Azure region (e.g. japaneast)"
}

variable "ai_services_name" {
  type        = string
  description = "Name of the Azure AI Services resource"
}

variable "custom_subdomain_name" {
  type        = string
  description = "Custom subdomain name for the AI Services resource (must be globally unique)"
}

variable "sku_name" {
  type        = string
  description = "SKU name (e.g. S0)"
  default     = "S0"
}

variable "public_network_access" {
  type        = string
  description = "Public network access setting: Enabled or Disabled"
  default     = "Enabled"
}

variable "local_authentication_enabled" {
  type        = bool
  description = "Enable local authentication"
  default     = true
}

variable "outbound_network_access_restricted" {
  type        = bool
  description = "Restrict outbound network access"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Resource tags"
  default     = {}
}

# =========
# Resource
# =========
resource "azurerm_ai_services" "foundry" {
  name                         = var.ai_services_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku_name                     = var.sku_name
  custom_subdomain_name        = var.custom_subdomain_name
  public_network_access        = var.public_network_access
  local_authentication_enabled = var.local_authentication_enabled
  outbound_network_access_restricted = var.outbound_network_access_restricted

  identity {
    type = "SystemAssigned"
  }

  # Optional: keep open by default (matches your sample intention)
  network_acls {
    default_action = "Allow"
    ip_rules       = []
    bypass         = "None"
  }

  tags = var.tags
}

# =======
# Outputs
# =======
output "ai_services_id" {
  value = azurerm_ai_services.foundry.id
}

output "ai_services_name" {
  value = azurerm_ai_services.foundry.name
}

output "ai_services_location" {
  value = azurerm_ai_services.foundry.location
}

output "custom_subdomain_name" {
  value = azurerm_ai_services.foundry.custom_subdomain_name
}
