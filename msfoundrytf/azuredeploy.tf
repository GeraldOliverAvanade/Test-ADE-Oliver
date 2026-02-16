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

variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "ai_services_name" { type = string }
variable "custom_subdomain_name" { type = string }

variable "sku_name" {
  type    = string
  default = "S0"
}

variable "public_network_access" {
  type    = string
  default = "Enabled"
}

variable "local_authentication_enabled" {
  type    = bool
  default = true
}

variable "outbound_network_access_restricted" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ✅ Create RG first
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_ai_services" "foundry" {
  name                         = var.ai_services_name
  location                     = azurerm_resource_group.rg.location
  resource_group_name          = azurerm_resource_group.rg.name
  sku_name                     = var.sku_name
  custom_subdomain_name        = var.custom_subdomain_name
  public_network_access        = var.public_network_access
  local_authentication_enabled = var.local_authentication_enabled
  outbound_network_access_restricted = var.outbound_network_access_restricted

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Allow"
    ip_rules       = []
    bypass         = "None"
  }

  tags = var.tags
}

output "resource_group_name" { value = azurerm_resource_group.rg.name }
output "ai_services_id"      { value = azurerm_ai_services.foundry.id }
