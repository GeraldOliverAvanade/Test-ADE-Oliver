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

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group to create"
}

variable "location" {
  type        = string
  description = "Azure region for the resource group (e.g. japaneast)"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "resource_group_location" {
  value = azurerm_resource_group.rg.location
}
