# Provider Configuration
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }
}

# Azure Provider
provider "azurerm" {
  features {}
  subscription_id = var.azure_sub_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}

# Generate a random three-digit number
resource "random_integer" "random_suffix" {
  min = 001
  max = 999
}

resource "random_string" "random_letters" {
  length  = 4
  special = false  # Excludes special characters
  upper   = false  # Excludes uppercase letters
  numeric = false  # Excludes numbers 
}

# Cloudflare provider setup
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  }
}

########################################################################################
# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.app_name}-rg-${var.environment}"
  location = var.location
}

########################################################################################
# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.app_name}-vnet-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
  depends_on = [azurerm_resource_group.rg]
}

########################################################################################
# AKS Subnet
resource "azurerm_subnet" "aks_subnet" {
  name                 = "${var.app_name}-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.aks_subnet_prefix

  depends_on = [azurerm_virtual_network.vnet]
}

########################################################################################
# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.app_name}-k8s-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.app_name}-dns-${var.environment}"

  default_node_pool {
    name            = "${var.app_name}nodes"
    node_count      = var.aks_node_count
    vm_size         = var.aks_vm_size
    os_disk_size_gb = var.aks_os_disk_size
    vnet_subnet_id  = azurerm_subnet.aks_subnet.id
  }

  service_principal {
    client_id     = var.azure_client_id
    client_secret = var.azure_client_secret
  }

  role_based_access_control_enabled = true

  depends_on = [azurerm_subnet.aks_subnet]
}

########################################################################################
# PostgreSQL Subnet
resource "azurerm_subnet" "postgres_subnet" {
  name                 = "${var.app_name}-pg-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.postgres_subnet_prefix

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }

  service_endpoints = ["Microsoft.Storage"]

  depends_on = [
    azurerm_virtual_network.vnet,
    azurerm_private_dns_zone.postgres_dns_zone
  ]
}

########################################################################################
# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres_dns_zone" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

########################################################################################
# DNS Zone VNet Link for PostgreSQL
resource "azurerm_private_dns_zone_virtual_network_link" "postgres_dns_vnet_link" {
  name                  = "${azurerm_postgresql_flexible_server.postgres.name}-dns-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false

  depends_on = [
    azurerm_postgresql_flexible_server.postgres,
    azurerm_virtual_network.vnet,
    azurerm_subnet.postgres_subnet
  ]
}

########################################################################################
# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "${var.app_name}-pg-server-${var.environment}${random_integer.random_suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = var.postgres_version
  administrator_login    = var.db_username
  administrator_password = var.db_password
  sku_name               = var.postgres_sku
  storage_mb             = var.postgres_storage_gb * 1024
  delegated_subnet_id    = azurerm_subnet.postgres_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres_dns_zone.id
  public_network_access_enabled = false
  geo_redundant_backup_enabled = false
  backup_retention_days        = var.postgres_backup_days
  depends_on = [
    azurerm_subnet.postgres_subnet,
    azurerm_private_dns_zone.postgres_dns_zone
  ]
  lifecycle {
    ignore_changes = [zone]
  }
}

########################################################################################
# Storage Subnet
resource "azurerm_subnet" "storage_subnet" {
  name                 = "${var.app_name}-storage-subnet-${var.environment}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.storage_subnet_prefix
  private_link_service_network_policies_enabled = false

  depends_on = [azurerm_virtual_network.vnet]
}

########################################################################################
# Storage Account
resource "azurerm_storage_account" "storage" {
  name                     = "${var.app_name}storage${var.environment}${random_integer.random_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Premium"
  account_replication_type = "LRS"
  account_kind             = "FileStorage"
  https_traffic_only_enabled = false

  depends_on = [azurerm_resource_group.rg]
}

########################################################################################
# NFS File Share
resource "azurerm_storage_share" "nfs_share" {
  name               = "${var.app_name}-fileshare-${var.environment}"
  storage_account_name = azurerm_storage_account.storage.name
  quota             = 100
  enabled_protocol  = "NFS"
}

########################################################################################
# Create Private DNS Zone for Storage
resource "azurerm_private_dns_zone" "storage_dns_zone" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

########################################################################################
# Create Private Endpoint
resource "azurerm_private_endpoint" "storage_private_endpoint" {
  name                = "${var.app_name}-nfs-private-endpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.storage_subnet.id

  private_service_connection {
    name                           = "${var.app_name}-nfs-private-connection"
    private_connection_resource_id = azurerm_storage_account.storage.id
    subresource_names              = ["file"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_dns_zone.id]
  }

  depends_on = [
    azurerm_storage_account.storage,
    azurerm_subnet.storage_subnet
  ]
}

########################################################################################
# Create Virtual Network Link to Private DNS Zone
resource "azurerm_private_dns_zone_virtual_network_link" "storage_dns_vnet_link" {
  name                  = "${var.app_name}-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false

  depends_on = [azurerm_virtual_network.vnet]
}

########################################################################################
# Install NGINX Ingress Controller using Helm
resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  namespace  = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.0.10"  # Ensure the version is compatible with your Kubernetes version

  create_namespace = true

  set {
    name  = "controller.replicaCount"
    value = "1"  # Number of replicas for high availability
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

locals {
  app_base_url = var.app_base_url != "" ? var.app_base_url : "http://${random_string.random_letters.result}.${var.location}.cloudapp.azure.com"
}


########################################################################################
# Install Bold Reports using Helm
resource "helm_release" "bold_reports" {
  name       = "boldreports"
  namespace  = var.bold_reports_namespace
  repository = "https://boldreports.github.io/bold-reports-kubernetes"
  chart      = "boldreports"
  version    = var.bold_reports_version  # Ensure the version is compatible with your Kubernetes version

  create_namespace = true

  set {
    name  = "namespace"
    value = var.bold_reports_namespace
  }

  set {
    name  = "appBaseUrl"
    value = local.app_base_url
  }

  set {
    name  = "clusterProvider"
    value = "aks" 
  }

  set {
    name  = "persistentVolume.aks.nfs.fileShareName"
    value = "${azurerm_storage_account.storage.name}/${azurerm_storage_share.nfs_share.name}"
  }

  set {
    name  = "persistentVolume.aks.nfs.hostName"
    value = "${azurerm_storage_account.storage.name}.file.core.windows.net" 
  }

  depends_on = [
    helm_release.nginx_ingress,
    azurerm_private_dns_zone_virtual_network_link.postgres_dns_vnet_link,
    azurerm_postgresql_flexible_server.postgres
  ]
}

########################################################################################
#Domain Maping
data "kubernetes_service" "nginx_ingress_service" {
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.bold_reports]
}

resource "cloudflare_record" "nginx_ingress" {
  count   = var.cloudflare_zone_id != "" ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = split(".", replace(replace(var.app_base_url , "https://", ""), "http://", ""))[0]
  value   = data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip
  type    = "A"  # A record for an IPv4 address
  ttl     = 300  # You can adjust the TTL as needed
  proxied = false  # Set to true if you want Cloudflare's proxy (e.g., CDN, security features)
}

data "azurerm_public_ips" "all" {
  resource_group_name = "MC_${azurerm_resource_group.rg.name}_${azurerm_kubernetes_cluster.aks.name}_${var.location}"
  depends_on = [helm_release.bold_reports]
}

# Find the public IP by filtering based on IP address
locals {
  matching_ip = [for ip in data.azurerm_public_ips.all.public_ips : ip if ip.ip_address == data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip]
}

resource "null_resource" "az_login" {
  count   = var.cloudflare_zone_id == "" ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
      az login --service-principal -t ${var.azure_tenant_id} -u ${var.azure_client_id} -p ${var.azure_client_secret}
    EOT
  }
  depends_on = [helm_release.bold_reports]
}

resource "null_resource" "set_subscrition" {
  count   = var.cloudflare_zone_id == "" ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
      az account set --subscription ${var.azure_sub_id}
    EOT
  }
  depends_on = [null_resource.az_login]
}

resource "null_resource" "update_public_ip_dns" {
  count   = var.cloudflare_zone_id == "" ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
      az network public-ip update --resource-group MC_${azurerm_resource_group.rg.name}_${azurerm_kubernetes_cluster.aks.name}_${var.location}  --name ${local.matching_ip[0].name}  --dns-name ${random_string.random_letters.result}
    EOT
  }
  depends_on = [null_resource.set_subscrition]
}

########################################################################################
# Create Bold TLS Secret
resource "kubernetes_secret" "bold_tls" {
  count   = var.tls_certificate_path != "" && var.tls_key_path != "" ? 1 : 0
  metadata {
    name      = "bold-tls"
    namespace = "bold-services"
  }

  data = {
    "tls.crt" = file(var.tls_certificate_path)  # Path to the certificate file
    "tls.key" = file(var.tls_key_path) # Path to the private key file
  }
  type = "kubernetes.io/tls"
  depends_on = [helm_release.bold_reports]
}

########################################################################################
output "Line_1" {
  value = "Your app base URL: ${local.app_base_url}"
}

output "Line_2" {
  value = "Your Nginx Ingress IP address: ${data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip}"
}

output "Line_3" {
  value = "Your PostgerSQL Server: ${azurerm_postgresql_flexible_server.postgres.fqdn}"
}

output "NOTE" {
  value = "If you have not mapped a domain, please map it to ${data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip}."
}