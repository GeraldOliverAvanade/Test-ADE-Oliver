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
# Storage Account
#################
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

variable "storage_account_kind" {
  type    = string
  default = "StorageV2"
}

variable "enable_large_file_share" {
  type    = bool
  default = false
}

#################
# File Share
#################
variable "enable_file_share" {
  type    = bool
  default = true
}

variable "file_share_name" {
  type    = string
  default = "fileshare"
}

variable "file_share_quota" {
  type    = number
  default = 100
}

#################
# Locals
#################
resource "random_string" "suffix" {
  length  = 8
  lower   = true
  special = false
}

locals {
  parsed_tags = try(jsondecode(var.tags), {})
  storage_account_name = var.storage_account_name != "" ? lower(var.storage_account_name) : "st${random_string.suffix.result}"
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
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = var.storage_account_kind

  min_tls_version          = "TLS1_2"
  large_file_share_enabled = var.enable_large_file_share

  tags = local.parsed_tags
}

#################
# File Share
#################
resource "azurerm_storage_share" "fileshare" {
  count              = var.enable_file_share ? 1 : 0
  name               = var.file_share_name
  storage_account_id = azurerm_storage_account.sa.id
  quota              = var.file_share_quota
}

#################
# Outputs
#################
output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "storage_account_id" {
  value = azurerm_storage_account.sa.id
}

output "primary_file_endpoint" {
  value = azurerm_storage_account.sa.primary_file_endpoint
}

output "file_share_name" {
  value = var.enable_file_share ? azurerm_storage_share.fileshare[0].name : null
}
