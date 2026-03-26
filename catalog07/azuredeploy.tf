terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.58.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
  description = "Azure region"
  default     = "japaneast"
}

variable "tags" {
  type        = string
  description = "Tags as JSON string"
  default     = "{}"
}

#################
# VNET
#################
variable "vnet_name" {
  type    = string
  default = "vnet-japaneast-01"
}

variable "vnet_address_space" {
  type    = string
  default = "172.21.0.0/24"
}

#################
# Log Analytics
#################
variable "log_analytics_name" {
  type    = string
  default = ""
}

variable "log_analytics_sku" {
  type    = string
  default = "PerGB2018"
}

variable "log_analytics_retention_in_days" {
  type    = number
  default = 30
}

#################
# Application Insights
#################
variable "application_insights_name" {
  type    = string
  default = ""
}

variable "application_insights_type" {
  type    = string
  default = "web"
}

#################
# Data / Locals
#################
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
  numeric = true
}

locals {
  parsed_tags = try(jsondecode(var.tags), {})

  vnet_address_space_list = [
    for s in split(",", var.vnet_address_space) : trimspace(s)
    if trimspace(s) != ""
  ]

  log_analytics_name_effective = trimspace(var.log_analytics_name) != "" ? trimspace(var.log_analytics_name) : "log-${random_string.suffix.result}"
  application_insights_name_effective = trimspace(var.application_insights_name) != "" ? trimspace(var.application_insights_name) : "appi-${random_string.suffix.result}"
}

#################
# Resource Group
#################
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.parsed_tags
}

#################
# VNET
#################
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = local.vnet_address_space_list
  tags                = local.parsed_tags
}

#################
# Log Analytics
#################
resource "azurerm_log_analytics_workspace" "log" {
  name                = local.log_analytics_name_effective
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = local.parsed_tags
}

#################
# Application Insights
#################
resource "azurerm_application_insights" "appi" {
  name                = local.application_insights_name_effective
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  workspace_id        = azurerm_log_analytics_workspace.log.id
  application_type    = var.application_insights_type
  tags                = local.parsed_tags
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

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.log.id
}

output "application_insights_id" {
  value = azurerm_application_insights.appi.id
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.appi.connection_string
  sensitive = true
}

output "application_insights_instrumentation_key" {
  value     = azurerm_application_insights.appi.instrumentation_key
  sensitive = true
}
