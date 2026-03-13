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

variable "vnet_name" {
  type    = string
  default = "vnet-japaneast-4"
}

variable "vnet_address_space" {
  type    = string
  default = "172.21.0.0/24"
}

variable "vm_subnet_name" {
  type    = string
  default = "snet-vm-01"
}

variable "vm_subnet_prefixes" {
  type    = string
  default = "172.21.0.0/26"
}

variable "bastion_subnet_prefixes" {
  type    = string
  default = "172.21.0.64/26"
}

variable "private_endpoint_subnet_name" {
  type    = string
  default = "snet-pe-01"
}

variable "private_endpoint_subnet_prefixes" {
  type    = string
  default = "172.21.0.128/26"
}

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
  type    = number
  default = 127
}

variable "enable_vm_public_ip" {
  type    = bool
  default = false
}

variable "rdp_source_prefixes" {
  type    = string
  default = ""
}

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
  type    = string
  default = "1"
}

variable "enable_auto_shutdown" {
  type    = bool
  default = true
}

variable "auto_shutdown_time_utc" {
  type    = string
  default = "1900"
}

variable "bastion_sku" {
  type    = string
  default = "Standard"
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

variable "enable_storage_private_endpoint" {
  type    = bool
  default = true
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

variable "key_vault_rbac_enabled" {
  type    = bool
  default = true
}

variable "enable_key_vault_private_endpoint" {
  type    = bool
  default = true
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

variable "enable_vm_backup" {
  type    = bool
  default = false
}

variable "enable_recovery_services_private_endpoint" {
  type    = bool
  default = false
}

#################
# Data / Locals
#################
data "azurerm_client_config" "current" {}

resource "random_string" "sa_suffix" {
  length  = 12
  upper   = false
  special = false
  numeric = true
}

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
  kv_name                        = trimspace(var.key_vault_name) != "" ? lower(trimspace(var.key_vault_name)) : "kv${substr(md5(var.resource_group_name), 0, 22)}"
  rsv_name                       = trimspace(var.recovery_services_vault_name) != "" ? trimspace(var.recovery_services_vault_name) : "rsv-${substr(md5(var.resource_group_name), 0, 16)}"

  blob_private_dns_zone_name     = "privatelink.blob.core.windows.net"
  keyvault_private_dns_zone_name = "privatelink.vaultcore.azure.net"

  # Adjust geo code if needed for your region.
  backup_private_dns_zone_name = "privatelink.jpe.backup.windowsazure.com"
  queue_private_dns_zone_name  = "privatelink.queue.core.windows.net"
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
# Network
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
  count                = (var.enable_storage_private_endpoint || var.enable_key_vault_private_endpoint || var.enable_recovery_services_private_endpoint) ? 1 : 0
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
# Public IPs
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

resource "azurerm_public_ip" "bastion_pip" {
  name                = "${var.vnet_name}-bastion-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.bastion_sku == "Standard" ? local.zone_list : null
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
# VM
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
# Auto Shutdown
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
# Bastion
#################
resource "azurerm_bastion_host" "bastion" {
  name                = "${var.vnet_name}-bastion"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = var.bastion_sku

  scale_units        = var.bastion_sku == "Standard" ? 2 : null
  copy_paste_enabled = var.bastion_sku == "Standard" ? true : null

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
  count                    = var.enable_storage_account ? 1 : 0
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
# Key Vault
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
# Private DNS Zones
#################
resource "azurerm_private_dns_zone" "blob" {
  count               = var.enable_storage_account && var.enable_storage_private_endpoint ? 1 : 0
  name                = local.blob_private_dns_zone_name
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.enable_storage_account && var.enable_storage_private_endpoint ? 1 : 0
  name                  = "${var.vnet_name}-blob-pdns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.parsed_tags
}

resource "azurerm_private_dns_zone" "kv" {
  count               = var.enable_key_vault && var.enable_key_vault_private_endpoint ? 1 : 0
  name                = local.keyvault_private_dns_zone_name
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  count                 = var.enable_key_vault && var.enable_key_vault_private_endpoint ? 1 : 0
  name                  = "${var.vnet_name}-kv-pdns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.kv[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.parsed_tags
}

resource "azurerm_private_dns_zone" "backup" {
  count               = var.enable_recovery_services_vault && var.enable_recovery_services_private_endpoint ? 1 : 0
  name                = local.backup_private_dns_zone_name
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "backup" {
  count                 = var.enable_recovery_services_vault && var.enable_recovery_services_private_endpoint ? 1 : 0
  name                  = "${var.vnet_name}-backup-pdns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.backup[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.parsed_tags
}

resource "azurerm_private_dns_zone" "queue" {
  count               = var.enable_recovery_services_vault && var.enable_recovery_services_private_endpoint ? 1 : 0
  name                = local.queue_private_dns_zone_name
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.parsed_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  count                 = var.enable_recovery_services_vault && var.enable_recovery_services_private_endpoint ? 1 : 0
  name                  = "${var.vnet_name}-queue-pdns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.queue[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = local.parsed_tags
}

#################
# Private Endpoints
#################
resource "azurerm_private_endpoint" "blob" {
  count               = var.enable_storage_account && var.enable_storage_private_endpoint ? 1 : 0
  name                = "pe-${local.storage_account_name_effective}-blob"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint[0].id
  tags                = local.parsed_tags

  private_service_connection {
    name                           = "psc-${local.storage_account_name_effective}-blob"
    private_connection_resource_id = azurerm_storage_account.sa[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}

resource "azurerm_private_endpoint" "kv" {
  count               = var.enable_key_vault && var.enable_key_vault_private_endpoint ? 1 : 0
  name                = "pe-${local.kv_name}-vault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint[0].id
  tags                = local.parsed_tags

  private_service_connection {
    name                           = "psc-${local.kv_name}-vault"
    private_connection_resource_id = azurerm_key_vault.kv[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv[0].id]
  }
}

resource "azurerm_private_endpoint" "rsv_backup" {
  count               = var.enable_recovery_services_vault && var.enable_recovery_services_private_endpoint ? 1 : 0
  name                = "pe-${local.rsv_name}-backup"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.private_endpoint[0].id
  tags                = local.parsed_tags

  private_service_connection {
    name                           = "psc-${local.rsv_name}-backup"
    private_connection_resource_id = azurerm_recovery_services_vault.rsv[0].id
    subresource_names              = ["AzureBackup"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.backup[0].id,
      azurerm_private_dns_zone.queue[0].id,
      azurerm_private_dns_zone.blob[0].id
    ]
  }
}

#################
# VM Backup
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
  value = var.enable_vm_public_ip ? azurerm_public_ip.vm_pip[0].ip_address : null
}

output "bastion_id" {
  value = azurerm_bastion_host.bastion.id
}

output "storage_account_name" {
  value = var.enable_storage_account ? azurerm_storage_account.sa[0].name : null
}

output "storage_account_id" {
  value = var.enable_storage_account ? azurerm_storage_account.sa[0].id : null
}

output "storage_private_endpoint_id" {
  value = var.enable_storage_account && var.enable_storage_private_endpoint ? azurerm_private_endpoint.blob[0].id : null
}

output "key_vault_id" {
  value = var.enable_key_vault ? azurerm_key_vault.kv[0].id : null
}

output "key_vault_private_endpoint_id" {
  value = var.enable_key_vault && var.enable_key_vault_private_endpoint ? azurerm_private_endpoint.kv[0].id : null
}

output "recovery_services_vault_id" {
  value = var.enable_recovery_services_vault ? azurerm_recovery_services_vault.rsv[0].id : null
}

output "recovery_services_private_endpoint_id" {
  value = var.enable_recovery_services_vault && var.enable_recovery_services_private_endpoint ? azurerm_private_endpoint.rsv_backup[0].id : null
}
