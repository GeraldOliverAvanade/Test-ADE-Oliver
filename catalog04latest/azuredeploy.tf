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

# Accept JSON string from ADE, e.g. {"env":"dev","owner":"oliver"}
variable "tags" {
  type        = string
  description = "Tags as JSON string"
  default     = "{}"
}

# Network
variable "vnet_name" {
  type    = string
  default = "vnet-japaneast-4"
}

# Accept comma-separated list, e.g. "172.21.0.0/16"
variable "vnet_address_space" {
  type    = string
  default = "172.21.0.0/24"
}

variable "vm_subnet_name" {
  type    = string
  default = "snet-vm-01"
}

# e.g. "172.21.0.0/26"
variable "vm_subnet_prefixes" {
  type    = string
  default = "172.21.0.0/26"
}

# Must be named exactly AzureBastionSubnet. Bastion requires /26 or larger.
variable "bastion_subnet_prefixes" {
  type    = string
  default = "172.21.0.64/26"
}

# Private Endpoint subnet
variable "private_endpoint_subnet_name" {
  type        = string
  description = "Subnet name for Private Endpoint"
  default     = "snet-pe-01"
}

variable "private_endpoint_subnet_prefixes" {
  type        = string
  description = "Comma-separated subnet prefixes for Private Endpoint subnet"
  default     = "172.21.0.128/26"
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

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 127
}

variable "enable_vm_public_ip" {
  type        = bool
  description = "Attach a Public IP to the VM NIC"
  default     = false
}

variable "rdp_source_prefixes" {
  type        = string
  description = "Comma-separated CIDRs allowed to RDP when enable_vm_public_ip=true"
  default     = ""
}

# OS Image
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

# Auto-shutdown
variable "enable_auto_shutdown" {
  type    = bool
  default = true
}

variable "auto_shutdown_time_utc" {
  type    = string
  default = "1900"
}

#################
# Storage Account + Private Endpoint
#################
variable "storage_account_name" {
  type        = string
  description = "Globally unique storage account name (3-24 lowercase letters/numbers). Leave empty to auto-generate."
  default     = ""
}

variable "storage_account_tier" {
  type        = string
  description = "Storage account tier"
  default     = "Standard"
}

variable "storage_account_replication_type" {
  type        = string
  description = "Storage account replication type"
  default     = "LRS"
}

variable "enable_storage_private_endpoint" {
  type        = bool
  description = "Create a Blob private endpoint and private DNS for the storage account"
  default     = true
}

#################
# Locals
#################
locals {
  parsed_tags = try(jsondecode(var.tags), {})

  vnet_address_space_list      = [for s in split(",", var.vnet_address_space) : trimspace(s) if trimspace(s) != ""]
  vm_subnet_prefixes_list      = [for s in split(",", var.vm_subnet_prefixes) : trimspace(s) if trimspace(s) != ""]
  bastion_subnet_prefixes_list = [for s in split(",", var.bastion_subnet_prefixes) : trimspace(s) if trimspace(s) != ""]
  pe_subnet_prefixes_list      = [for s in split(",", var.private_endpoint_subnet_prefixes) : trimspace(s) if trimspace(s) != ""]
  rdp_source_prefixes_list     = [for s in split(",", var.rdp_source_prefixes) : trimspace(s) if trimspace(s) != ""]

  zone_list = trimspace(var.zone) == "" ? [] : [trimspace(var.zone)]

  computer_name = substr(replace(var.vm_name, "_", "-"), 0, 15)

  storage_account_name_effective = trimspace(var.storage_account_name) != "" ? lower(trimspace(var.storage_account_name)) : "st${random_string.sa_suffix.result}"

  blob_private_dns_zone_name = "privatelink.blob.core.windows.net"
}

#################
# Random suffix for storage name if omitted
#################
resource "random_string" "sa_suffix" {
  length  = 12
  upper   = false
  special = false
  numeric = true
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
# VNet + Subnets
#################
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = local.vnet_address_space_list
  tags                = local.parsed_tags
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

resource "azurerm_subnet" "private_endpoint" {
  count                = var.enable_storage_private_endpoint ? 1 : 0
  name                 = var.private_endpoint_subnet_name
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = local.pe_subnet_prefixes_list

  private_endpoint_network_policies = "Disabled"
}

#################
# NSG
#################
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags

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
    for_each = var.enable_vm_public_ip && length(local.rdp_source_prefixes_list) > 0 ? local.rdp_source_prefixes_list : []
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
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.parsed_tags
}

#################
# NIC
#################
resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags

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

  zone = trimspace(var.zone) == "" ? null : trimspace(var.zone)

  tags = local.parsed_tags
}

#################
# Auto-shutdown schedule
#################
resource "azurerm_dev_test_global_vm_shutdown_schedule" "shutdown" {
  count = var.enable_auto_shutdown ? 1 : 0

  virtual_machine_id    = azurerm_windows_virtual_machine.vm.id
  location              = azurerm_resource_group.rg.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time_utc
  timezone              = "UTC"
  tags                  = local.parsed_tags

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
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.zone_list
  tags                = local.parsed_tags
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

  tags = local.parsed_tags
}

#################
# Storage Account
#################
resource "azurerm_storage_account" "sa" {
  name                     = local.storage_account_name_effective
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type

  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false

  tags = local.parsed_tags
}

#################
# Private DNS Zone + VNet Link
#################
resource "azurerm_private_dns_zone" "blob" {
  count               = var.enable_storage_private_endpoint ? 1 : 0
  name                = local.blob_private_dns_zone_name
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.enable_storage_private_endpoint ? 1 : 0
  name                  = "${var.vnet_name}-blob-pdns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.parsed_tags
}

#################
# Blob Private Endpoint
#################
resource "azurerm_private_endpoint" "blob" {
  count               = var.enable_storage_private_endpoint ? 1 : 0
  name                = "pe-${local.storage_account_name_effective}-blob"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint[0].id
  tags                = local.parsed_tags

  private_service_connection {
    name                           = "psc-${local.storage_account_name_effective}-blob"
    private_connection_resource_id = azurerm_storage_account.sa.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
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

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "storage_account_id" {
  value = azurerm_storage_account.sa.id
}

output "private_endpoint_id" {
  value       = var.enable_storage_private_endpoint ? azurerm_private_endpoint.blob[0].id : null
  description = "Blob Private Endpoint ID"
}

output "private_dns_zone_id" {
  value       = var.enable_storage_private_endpoint ? azurerm_private_dns_zone.blob[0].id : null
  description = "Blob Private DNS Zone ID"
}
