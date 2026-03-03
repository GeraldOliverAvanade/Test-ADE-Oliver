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

# Network
variable "vnet_name" {
  type    = string
  default = "vnet-japaneast-4"
}

# Accept comma-separated list, e.g. "172.21.0.0/16"
variable "vnet_address_space" {
  type    = string
  default = "172.21.0.0/16"
}

variable "vm_subnet_name" {
  type    = string
  default = "snet-japaneast-1"
}

# e.g. "172.21.0.0/24"
variable "vm_subnet_prefixes" {
  type    = string
  default = "172.21.0.0/24"
}

# Must be named exactly AzureBastionSubnet
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

variable "admin_username" {
  type    = string
  default = "adminuser"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "Windows admin password"
}

# VM OS Disk
variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 127
}

# VM Public IP (for direct access). Bastion still has its own public IP regardless.
variable "enable_vm_public_ip" {
  type        = bool
  description = "Attach a Public IP to the VM NIC"
  default     = false
}

# Optional: allow RDP from these CIDRs if VM has public IP enabled
# Comma-separated list, e.g. "203.0.113.10/32,203.0.113.11/32"
variable "rdp_source_prefixes" {
  type        = string
  description = "Comma-separated CIDRs allowed to RDP when enable_vm_public_ip=true"
  default     = ""
}

# OS Image (user-definable)
variable "image_publisher" {
  type    = string
  default = "MicrosoftWindowsServer"
}

variable "image_offer" {
  type    = string
  default = "WindowsServer"
}

variable "image_sku" {
  type    = string
  default = "2025-datacenter-azure-edition"
}

variable "image_version" {
  type    = string
  default = "latest"
}

variable "zone" {
  type        = string
  description = "Availability Zone number as string (e.g. '1'). Leave empty for no zone."
  default     = "1"
}

# Auto-shutdown (optional)
variable "enable_auto_shutdown" {
  type    = bool
  default = true
}

# HHmm in UTC, e.g. 1900
variable "auto_shutdown_time_utc" {
  type    = string
  default = "1900"
}

locals {
  vnet_address_space_list      = [for s in split(",", var.vnet_address_space) : trimspace(s)]
  vm_subnet_prefixes_list      = [for s in split(",", var.vm_subnet_prefixes) : trimspace(s)]
  bastion_subnet_prefixes_list = [for s in split(",", var.bastion_subnet_prefixes) : trimspace(s)]
  rdp_source_prefixes_list     = [for s in split(",", var.rdp_source_prefixes) : trimspace(s) if trimspace(s) != ""]

  # Convert zone to list for resources that accept list. If empty, use null/empty.
  zone_list = (trimspace(var.zone) == "" ? [] : [trimspace(var.zone)])

  # Windows computer_name has a 15-char limit. Derive it from vm_name safely.
  computer_name = substr(replace(var.vm_name, "_", "-"), 0, 15)
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
# NSG
# - Always allow RDP only from Bastion subnet
# - Optionally allow RDP from user CIDRs if VM has public IP enabled
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

  dynamic "security_rule" {
    for_each = (var.enable_vm_public_ip && length(local.rdp_source_prefixes_list) > 0) ? local.rdp_source_prefixes_list : []
    content {
      name                       = "Allow-RDP-From-${replace(replace(security_rule.value, "/", "-"), ".", "-")}"
      priority                   = 400 + index(local.rdp_source_prefixes_list, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
      description                = "Allow RDP from specified source when VM Public IP is enabled"
    }
  }
}

#################
# VM Public IP (optional)
#################
resource "azurerm_public_ip" "vm_pip" {
  count               = var.enable_vm_public_ip ? 1 : 0
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  allocation_method = "Static"
  sku              = "Standard"

  tags = var.tags
}

#################
# NIC (Public IP optional)
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
# Windows VM
#################
resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  computer_name       = local.computer_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password

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
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  # Optional zone
  zone = (trimspace(var.zone) == "" ? null : trimspace(var.zone))

  tags = var.tags
}

#################
# Auto-shutdown schedule (optional)
#################
resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  count = var.enable_auto_shutdown ? 1 : 0

  virtual_machine_id    = azurerm_windows_virtual_machine.vm.id
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

  tags = var.tags
}

resource "azurerm_bastion_host" "bastion" {
  name                = "${var.vnet_name}-bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  scale_units         = 2

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
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "vm_id" {
  value = azurerm_windows_virtual_machine.vm.id
}

output "vm_public_ip" {
  value       = var.enable_vm_public_ip ? azurerm_public_ip.vm_pip[0].ip_address : null
  description = "VM Public IP (only if enabled)"
}

output "bastion_id" {
  value = azurerm_bastion_host.bastion.id
}
