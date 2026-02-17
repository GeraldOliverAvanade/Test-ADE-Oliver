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

#################
# Variables
#################
variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region (e.g. japaneast)"
}

variable "ai_services_name" {
  type        = string
  description = "Azure AI Services resource name"
}

variable "custom_subdomain_name" {
  type        = string
  description = "Globally unique custom subdomain name"
}

variable "sku_name" {
  type        = string
  description = "SKU (e.g. S0)"
  default     = "S0"
}

variable "public_network_access" {
  type        = string
  description = "Enabled or Disabled"
  default     = "Disabled"
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

# Network inputs (ADE-friendly as strings)
variable "vnet_name" {
  type    = string
  default = "vnet-foundry-ade"
}

# Accept comma-separated list in ADE, e.g. "10.10.0.0/16,10.11.0.0/16"
variable "vnet_address_space" {
  type    = string
  default = "10.10.0.0/16"
}

variable "pe_subnet_name" {
  type    = string
  default = "snet-private-endpoints"
}

# Accept comma-separated list in ADE, e.g. "10.10.1.0/24"
variable "pe_subnet_prefixes" {
  type    = string
  default = "10.10.1.0/24"
}

locals {
  vnet_address_space_list = [for s in split(",", var.vnet_address_space) : trimspace(s)]
  pe_subnet_prefixes_list = [for s in split(",", var.pe_subnet_prefixes) : trimspace(s)]
}

#################
# Resource Group
#################
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

#################
# VNet + Subnet (for Private Endpoint)
#################
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = local.vnet_address_space_list
  tags                = var.tags
}

resource "azurerm_subnet" "pe" {
  name                 = var.pe_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = local.pe_subnet_prefixes_list

  # Your runner accepted this schema previously
  private_endpoint_network_policies = "Disabled"
}

#################
# Azure AI Services (Foundry)
#################
resource "azurerm_ai_services" "foundry" {
  name                               = var.ai_services_name
  location                           = azurerm_resource_group.rg.location
  resource_group_name                = azurerm_resource_group.rg.name
  sku_name                           = var.sku_name
  custom_subdomain_name              = var.custom_subdomain_name
  public_network_access              = var.public_network_access
  local_authentication_enabled       = var.local_authentication_enabled
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

#################
# Private DNS (Cognitive Services / AI Services)
#################
resource "azurerm_private_dns_zone" "ai" {
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "ai_link" {
  name                  = "link-${var.vnet_name}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.ai.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

#################
# Private DNS (OpenAi)
#################

# Private DNS (Azure OpenAI)
resource "azurerm_private_dns_zone" "openai" {
  name                = "privatelink.openai.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "openai_link" {
  name                  = "link-openai-${var.vnet_name}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.openai.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}


#################
# Private Endpoint + DNS Zone Group (inline)
#################
resource "azurerm_private_endpoint" "ai_pe" {
  name                = "pe-${var.ai_services_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.ai_services_name}"
    private_connection_resource_id = azurerm_ai_services.foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "ai-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.ai.id,azurerm_private_dns_zone.openai.id]
  }
}

#################
# Outputs
#################
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "ai_services_id" {
  value = azurerm_ai_services.foundry.id
}

output "private_endpoint_id" {
  value = azurerm_private_endpoint.ai_pe.id
}

output "private_dns_zone_name" {
  value = azurerm_private_dns_zone.ai.name
}
