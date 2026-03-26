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
  type = string
}

variable "location" {
  type    = string
  default = "japaneast"
}

variable "tags" {
  type    = string
  default = "{}"
}

#################
# Storage
#################
variable "enable_storage_account" {
  type    = bool
  default = true
}

variable "storage_account_name" {
  type    = string
  default = ""
}

variable "storage_account_tier" {
  type    = string
  default = "Standard"
}

variable "storage_account_replication_type" {
  type    = string
  default = "LRS"
}

#################
# Key Vault
#################
variable "enable_key_vault" {
  type    = bool
  default = true
}

variable "key_vault_name" {
  type    = string
  default = ""
}

variable "key_vault_sku" {
  type    = string
  default = "standard"
}

#################
# Recovery Services Vault
#################
variable "enable_recovery_services_vault" {
  type    = bool
  default = true
}

variable "recovery_services_vault_name" {
  type    = string
  default = ""
}

#################
# Log Analytics
#################
variable "log_analytics_name" {
  type    = string
  default = ""
}

#################
# Data / Locals
#################
data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 8
  lower   = true
  special = false
}

locals {
  parsed_tags = try(jsondecode(var.tags), {})

  storage_account_name = var.storage_account_name != "" ? lower(var.storage_account_name) : "st${random_string.suffix.result}"
  key_vault_name       = var.key_vault_name != "" ? lower(var.key_vault_name) : "kv${random_string.suffix.result}"
  rsv_name             = var.recovery_services_vault_name != "" ? var.recovery_services_vault_name : "rsv-${random_string.suffix.result}"
  log_name             = var.log_analytics_name != "" ? var.log_analytics_name : "log-${random_string.suffix.result}"
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
# Storage Account
#################
resource "azurerm_storage_account" "sa" {
  count                    = var.enable_storage_account ? 1 : 0
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type

  min_tls_version = "TLS1_2"

  tags = local.parsed_tags
}

#################
# Key Vault
#################
resource "azurerm_key_vault" "kv" {
  count               = var.enable_key_vault ? 1 : 0
  name                = local.key_vault_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = var.key_vault_sku

  enable_rbac_authorization = true

  tags = local.parsed_tags
}

#################
# Recovery Services Vault
#################
resource "azurerm_recovery_services_vault" "rsv" {
  count               = var.enable_recovery_services_vault ? 1 : 0
  name                = local.rsv_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  soft_delete_enabled = true

  tags = local.parsed_tags
}

#################
# Log Analytics
#################
resource "azurerm_log_analytics_workspace" "log" {
  name                = local.log_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = local.parsed_tags
}

#################
# Outputs
#################
output "storage_account_name" {
  value = var.enable_storage_account ? azurerm_storage_account.sa[0].name : null
}

output "key_vault_id" {
  value = var.enable_key_vault ? azurerm_key_vault.kv[0].id : null
}

output "recovery_services_vault_id" {
  value = var.enable_recovery_services_vault ? azurerm_recovery_services_vault.rsv[0].id : null
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.log.id
}
