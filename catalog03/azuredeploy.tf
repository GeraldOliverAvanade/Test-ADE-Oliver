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

#################
# Optional Services
#################

# Key Vault
variable "enable_key_vault" {
  type    = bool
  default = true
}

variable "key_vault_name" {
  type        = string
  description = "Key Vault name (3-24 chars, alphanumeric). Leave empty to auto-generate."
  default     = ""
}

variable "key_vault_sku" {
  type        = string
  description = "standard or premium"
  default     = "standard"
}

variable "key_vault_rbac_enabled" {
  type    = bool
  default = true
}

# Log Analytics
variable "enable_log_analytics" {
  type    = bool
  default = true
}

variable "log_analytics_name" {
  type        = string
  description = "Log Analytics Workspace name. Leave empty to auto-generate."
  default     = ""
}

variable "log_analytics_retention_days" {
  type    = number
  default = 30
}

# Recovery Services Vault (RSC)
variable "enable_recovery_services_vault" {
  type    = bool
  default = true
}

variable "recovery_services_vault_name" {
  type        = string
  description = "Recovery Services Vault name. Leave empty to auto-generate."
  default     = ""
}

variable "enable_vm_backup" {
  type    = bool
  default = false
}

# Bastion SKU
variable "bastion_sku" {
  type        = string
  description = "Bastion SKU: Basic or Standard"
  default     = "Basic"
}

#################
# Storage Account (optional)  ✅ NEW
#################
variable "enable_storage_account" {
  type    = bool
  default = true
}

variable "storage_account_name" {
  type        = string
  description = "Storage Account name (3-24 lowercase letters/numbers). Leave empty to auto-generate."
  default     = ""
}

variable "storage_account_tier" {
  type        = string
  description = "Standard or Premium"
  default     = "Standard"
}

variable "storage_account_replication_type" {
  type        = string
  description = "LRS, GRS, RAGRS, ZRS"
  default     = "LRS"
}

#################
# Locals / Data
#################
data "azurerm_client_config" "current" {}

locals {
  vnet_address_space_list      = [for s in split(",", var.vnet_address_space) : trimspace(s)]
  vm_subnet_prefixes_list      = [for s in split(",", var.vm_subnet_prefixes) : trimspace(s)]
  bastion_subnet_prefixes_list = [for s in split(",", var.bastion_subnet_prefixes) : trimspace(s)]
  rdp_source_prefixes_list     = [for s in split(",", var.rdp_source_prefixes) : trimspace(s) if trimspace(s) != ""]

  zone_list = (trimspace(var.zone) == "" ? [] : [trimspace(var.zone)])

  # Safe defaults (avoid global name collisions + KV rules)
  # Key Vault: 3-24, alphanumeric only. ("kv" + 22 hex chars = 24)
  kv_name  = (trimspace(var.key_vault_name) != "" ? lower(var.key_vault_name) : "kv${substr(md5(var.resource_group_name), 0, 22)}")

  # Log Analytics: 4-63, letters/numbers/-; keep it simple as alnum
  law_name = (trimspace(var.log_analytics_name) != "" ? lower(var.log_analytics_name) : "law${substr(md5(var.resource_group_name), 0, 20)}")

  # RSV: allow dash, max 50
  rsv_name = (trimspace(var.recovery_services_vault_name) != "" ? var.recovery_services_vault_name : "rsv-${substr(md5(var.resource_group_name), 0, 16)}")

  # Storage Account: 3-24, lowercase letters/numbers only
  sa_name  = (trimspace(var.storage_account_name) != "" ? lower(var.storage_account_name) : "st${substr(md5(var.resource_group_name), 0, 20)}")
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
# Key Vault (optional)
#################
resource "azurerm_key_vault" "kv" {
  count               = var.enable_key_vault ? 1 : 0
  name                = local.kv_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = var.key_vault_sku

  enable_rbac_authorization  = var.key_vault_rbac_enabled
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = var.tags
}

#################
# Log Analytics (optional)
#################
resource "azurerm_log_analytics_workspace" "law" {
  count               = var.enable_log_analytics ? 1 : 0
  name                = local.law_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku               = "PerGB2018"
  retention_in_days = var.log_analytics_retention_days

  tags = var.tags
}

#################
# Recovery Services Vault (optional)
#################
resource "azurerm_recovery_services_vault" "rsv" {
  count               = var.enable_recovery_services_vault ? 1 : 0
  name                = local.rsv_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  soft_delete_enabled = true

  tags = var.tags
}

#################
# Storage Account (optional) ✅ NEW
#################
resource "azurerm_storage_account" "sa" {
  count               = var.enable_storage_account ? 1 : 0
  name                = local.sa_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type

  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false

  tags = var.tags
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
# Windows VM
#################
resource "azurerm_windows_virtual_machine" "vm" {
  name                = var.vm_name
  computer_name       = "defaultpc"
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

  zone = (trimspace(var.zone) == "" ? null : trimspace(var.zone))

  tags = var.tags
}

#################
# VM Backup (optional)
#################
resource "azurerm_backup_policy_vm" "vm_policy" {
  count               = (var.enable_recovery_services_vault && var.enable_vm_backup) ? 1 : 0
  name                = "vm-daily-policy"
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv[0].name

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 7
  }
}

resource "azurerm_backup_protected_vm" "vm_backup" {
  count               = (var.enable_recovery_services_vault && var.enable_vm_backup) ? 1 : 0
  resource_group_name = azurerm_resource_group.rg.name
  recovery_vault_name = azurerm_recovery_services_vault.rsv[0].name
  source_vm_id        = azurerm_windows_virtual_machine.vm.id
  backup_policy_id    = azurerm_backup_policy_vm.vm_policy[0].id
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

  # Zones mainly used with Standard Bastion; keep null for Basic to avoid mismatch headaches
  zones = (var.bastion_sku == "Standard" ? local.zone_list : null)

  tags = var.tags
}

resource "azurerm_bastion_host" "bastion" {
  name                = "${var.vnet_name}-bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku = var.bastion_sku

  # Standard-only settings; set null for Basic
  scale_units        = (var.bastion_sku == "Standard" ? 2 : null)
  copy_paste_enabled = (var.bastion_sku == "Standard" ? true : null)

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

output "key_vault_id" {
  value       = var.enable_key_vault ? azurerm_key_vault.kv[0].id : null
  description = "Key Vault ID (if enabled)"
}

output "log_analytics_workspace_id" {
  value       = var.enable_log_analytics ? azurerm_log_analytics_workspace.law[0].id : null
  description = "Log Analytics Workspace ID (if enabled)"
}

output "recovery_services_vault_id" {
  value       = var.enable_recovery_services_vault ? azurerm_recovery_services_vault.rsv[0].id : null
  description = "Recovery Services Vault ID (if enabled)"
}

# Storage outputs ✅ NEW
output "storage_account_id" {
  value       = var.enable_storage_account ? azurerm_storage_account.sa[0].id : null
  description = "Storage Account ID (if enabled)"
}

output "storage_account_name" {
  value       = var.enable_storage_account ? azurerm_storage_account.sa[0].name : null
  description = "Storage Account Name (if enabled)"
}
