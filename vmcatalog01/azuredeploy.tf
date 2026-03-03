terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.58.0"
    }
  }
}

provider "azurerm" {
  features {}
}

#################
# Variables (ADE-friendly)
#################
variable "resource_group_name" {
  type        = string
  description = "Resource group name"
}

variable "location" {
  type        = string
  description = "Azure region (e.g. japaneast)"
  default     = "japaneast"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# OS
variable "os_type" {
  type        = string
  description = "windows or linux"
  default     = "windows"
  validation {
    condition     = contains(["windows", "linux"], lower(var.os_type))
    error_message = "os_type must be 'windows' or 'linux'."
  }
}

# Credentials
variable "admin_username" {
  type    = string
  default = "adminuser"
}

# Windows password (required if os_type=windows)
variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Windows admin password (required for Windows)"
  default     = ""
}

# Linux SSH key (required if os_type=linux)
variable "ssh_public_key" {
  type        = string
  description = "SSH public key (required for Linux)"
  default     = ""
}

# Network
variable "vnet_name" {
  type    = string
  default = "vnet-japaneast-4"
}

variable "vnet_address_space" {
  type    = string
  default = "172.21.0.0/16"
}

variable "vm_subnet_name" {
  type    = string
  default = "snet-japaneast-1"
}

variable "vm_subnet_prefixes" {
  type    = string
  default = "172.21.0.0/24"
}

variable "bastion_subnet_prefixes" {
  type    = string
  default = "172.21.1.0/26"
}

# VM
variable "vm_name" {
  type    = string
  default = "vm-test-oliver-01"
}

variable "vm_size" {
  type    = string
  default = "Standard_E2s_v3"
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 127
}

# VM Public IP toggle
variable "enable_vm_public_ip" {
  type        = bool
  description = "If true, attach a public IP to the VM NIC"
  default     = false
}

# Zone (optional)
variable "zone" {
  type        = string
  description = "Availability Zone number as string (e.g. '1'). Leave empty for no zone."
  default     = "1"
}

# Auto-shutdown (Windows only)
variable "enable_auto_shutdown" {
  type    = bool
  default = true
}

variable "auto_shutdown_time_utc" {
  type    = string
  default = "1900"
}

#################
# Locals
#################
locals {
  vnet_address_space_list         = [for s in split(",", var.vnet_address_space) : trimspace(s)]
  vm_subnet_prefixes_list         = [for s in split(",", var.vm_subnet_prefixes) : trimspace(s)]
  bastion_subnet_prefixes_list    = [for s in split(",", var.bastion_subnet_prefixes) : trimspace(s)]
  zone_list                       = (trimspace(var.zone) == "" ? [] : [trimspace(var.zone)])
  zone_value                      = (trimspace(var.zone) == "" ? null : trimspace(var.zone))

  is_windows = lower(var.os_type) == "windows"
  is_linux   = lower(var.os_type) == "linux"

  # Windows computer_name (NetBIOS) must be <= 15 chars.
  # Remove invalid chars, cut to 15, and avoid trailing '-'.
  computer_name_15 = substr(regexreplace(var.vm_name, "[^0-9A-Za-z-]", ""), 0, 15)
  computer_name    = trim(local.computer_name_15, "-")
}

#################
# Basic validation (fail fast)
#################
resource "terraform_data" "validate" {
  input = "validate"

  lifecycle {
    precondition {
      condition     = local.is_windows || local.is_linux
      error_message = "os_type must be 'windows' or 'linux'."
    }
    precondition {
      condition     = (!local.is_windows) || (length(var.admin_password) >= 1)
      error_message = "admin_password is required when os_type=windows."
    }
    precondition {
      condition     = (!local.is_linux) || (length(var.ssh_public_key) >= 1)
      error_message = "ssh_public_key is required when os_type=linux."
    }
    precondition {
      condition     = length(local.computer_name) >= 1
      error_message = "Derived computer_name became empty. Set vm_name starting with letters/numbers."
    }
  }
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
# VNet + Subnets
#################
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = local.vnet_address_space_list
  tags                = var.tags
}

resource "azurerm_subnet" "vm" {
  name                 = var.vm_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = local.vm_subnet_prefixes_list

  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = local.bastion_subnet_prefixes_list

  private_endpoint_network_policies = "Disabled"
}

#################
# NSG (RDP only from Bastion subnet)
#################
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP-From-AzureBastionSubnet"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = local.bastion_subnet_prefixes_list[0]
    destination_address_prefix = "*"
    description                = "Allow RDP from AzureBastionSubnet only"
  }
}

#################
# Optional VM Public IP
#################
resource "azurerm_public_ip" "vm_pip" {
  count               = var.enable_vm_public_ip ? 1 : 0
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method = "Static"
  sku              = "Standard"
  zones            = local.zone_list
  tags             = var.tags
}

#################
# NIC
#################
resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    primary                       = true
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_vm_public_ip ? azurerm_public_ip.vm_pip[0].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

#################
# Windows VM (os_type=windows)
#################
resource "azurerm_windows_virtual_machine" "vm_win" {
  count = local.is_windows ? 1 : 0

  name                = var.vm_name
  computer_name       = local.computer_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [azurerm_network_interface.nic.id]

  provision_vm_agent         = true
  allow_extension_operations = true
  enable_automatic_updates   = true
  patch_mode                 = "AutomaticByPlatform"
  patch_assessment_mode      = "ImageDefault"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }

  zone = local.zone_value
  tags = var.tags

  depends_on = [terraform_data.validate]
}

#################
# Linux VM (os_type=linux)
#################
resource "azurerm_linux_virtual_machine" "vm_linux" {
  count = local.is_linux ? 1 : 0

  name                = var.vm_name
  computer_name       = local.computer_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  zone = local.zone_value
  tags = var.tags

  depends_on = [terraform_data.validate]
}

#################
# Auto-shutdown (Windows only)
#################
resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  count = (var.enable_auto_shutdown && local.is_windows) ? 1 : 0

  virtual_machine_id    = azurerm_windows_virtual_machine.vm_win[0].id
  location              = azurerm_resource_group.rg.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time_utc
  timezone              = "UTC"
  tags                  = var.tags

  notification_settings {
    enabled         = false
    time_in_minutes = 30
    email           = ""
    webhook_url     = ""
  }
}

#################
# Bastion + Public IP
#################
resource "azurerm_public_ip" "bastion_pip" {
  name                = "${var.vnet_name}-bastion-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method = "Static"
  sku              = "Standard"
  zones            = local.zone_list
  tags             = var.tags
}

resource "azurerm_bastion_host" "bastion" {
  name                = "${var.vnet_name}-bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku         = "Standard"
  scale_units = 2
  copy_paste_enabled = true

  ip_configuration {
    name                 = "IpConf"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }

  tags = var.tags
}

#################
# Outputs
#################
output "resource_group_name" { value = azurerm_resource_group.rg.name }
output "vnet_id"            { value = azurerm_virtual_network.vnet.id }
output "bastion_id"         { value = azurerm_bastion_host.bastion.id }

output "computer_name_used" { value = local.computer_name }

output "vm_id" {
  value = local.is_windows ? azurerm_windows_virtual_machine.vm_win[0].id : azurerm_linux_virtual_machine.vm_linux[0].id
}
