provider "azurerm" {
  features {}
}

variable "db_password" {
  type = string
}

variable "resource_group_name" {
  type = string
}

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "azurerm_app_service_plan" "asp" {
  name                = "asp-terraform"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true

  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "as" {
  name                = "as-terraform"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.asp.id

  site_config {
    linux_fx_version = "DOCKER|nginx"
  }
}

resource "azurerm_mysql_flexible_server" "mysql" {
  name                = "mysql-terraform"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku_name            = "GP_Standard_D2ds_v4"
  version             = "5.7"
  administrator_login = "mysqladmin"
  administrator_password = var.db_password

  storage {
    size_gb = 20
  }

  high_availability {
    mode = "ZoneRedundant"
  }

  tags = {
    environment = "dev"
  }
}
