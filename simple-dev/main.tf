terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# If ADE is already creating/providing the resource group, you usually don't create it here.
# You just deploy into the existing RG and location.
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "azurerm_storage_account" "sa" {
  name                     = lower("${var.envName}sa")
  resource_group_name      = data.azurerm_resource_group.rg.name
  location                 = var.location != "" ? var.location : data.azurerm_resource_group.rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
}
