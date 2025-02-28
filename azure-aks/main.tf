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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0"
    }
  }
}

# Azure domain map (azure_domain_subscription)
provider "azurerm" {
  alias           = "azure_domain_subscription"
  features {}
  subscription_id = var.azure_domain_sub_id != "" ? var.azure_domain_sub_id : var.azure_sub_id
}

# Default Azure Provider (Using Variables)
provider "azurerm" {
  features {}
  subscription_id = var.azure_sub_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}

# Fetch the existing Azure DNS Zone in Subscription A
data "azurerm_dns_zone" "azure_zone" {
  count               = var.azure_domain_name != "" && var.azure_domain_rg_name != "" ? 1 : 0
  provider            = azurerm.azure_domain_subscription
  name                = var.azure_domain_name
  resource_group_name = var.azure_domain_rg_name
}

# Retrieve Key Vault
data "azurerm_key_vault" "bold_reports_secret" {
  count               = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name                = var.boldreports_secret_vault_name
  resource_group_name = var.boldreports_secret_vault_rg_name
}

# Retrieve Storage Account Name from Key Vault Secret
data "azurerm_key_vault_secret" "app-base-url" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "app-base-url"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "boldreports-email" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "boldreports-email"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "boldreports-password" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "boldreports-password"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "boldreports-unlock-key" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "boldreports-unlock-key"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "db-username" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "db-username"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "db-password" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "db-password"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "tls-certificate-path" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "tls-certificate-path"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "tls-key-path" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "tls-key-path"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "cloudflare-zone-id" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "cloudflare-zone-id"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "cloudflare-api-token" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "cloudflare-api-token"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_reports_secret[0].id
}

data "azurerm_key_vault_secret" "azure-domain-sub-id" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "azure-domain-sub-id"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_bi_secret[0].id
}

data "azurerm_key_vault_secret" "azure-domain-name" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "azure-domain-name"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_bi_secret[0].id
}

data "azurerm_key_vault_secret" "azure-domain-rg-name" {
  count        = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? 1 : 0
  name         = "azure-domain-rg-name"  # Replace with your secret name in Key Vault
  key_vault_id = data.azurerm_key_vault.bold_bi_secret[0].id
}

locals {
  # Use the Key Vault secret if available, otherwise fallback to the provided variable or a default value
  app_base_url          = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.app-base-url[0].value : coalesce(var.app_base_url, "https://${random_string.random_letters.result}.${var.location}.cloudapp.azure.com")
  cloudflare_api_token  = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.cloudflare-api-token[0].value : coalesce(var.cloudflare_api_token, "dummytokenplaceholdedummytokenplaceholde")
  cloudflare_zone_id    = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.cloudflare-zone-id[0].value : var.cloudflare_zone_id
  boldreports_email          = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.boldreports-email[0].value : var.boldreports_email
  boldreports_password       = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.boldreports-password[0].value : var.boldreports_password
  boldreports_unlock_key     = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.boldreports-unlock-key[0].value : var.boldreports_unlock_key
  db_username           = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.db-username[0].value : var.db_username
  db_password           = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.db-password[0].value : var.db_password
  tls_certificate_path  = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.tls-certificate-path[0].value : var.tls_certificate_path
  tls_key_path          = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.tls-key-path[0].value : var.tls_key_path

  azure_domain_sub_id   = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.azure-domain-sub-id[0].value : var.azure_domain_sub_id
  azure_domain_name     = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.azure-domain-name[0].value : var.azure_domain_name
  azure_domain_rg_name  = var.boldreports_secret_vault_name != "" && var.boldreports_secret_vault_rg_name != "" ? data.azurerm_key_vault_secret.azure-domain-rg-name[0].value : var.azure_domain_rg_name

  output_app_base_url   = var.app_base_url != "" ? var.app_base_url : "https://${random_string.random_letters.result}.${var.location}.cloudapp.azure.com"
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
  api_token = local.cloudflare_api_token
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

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  load_config_file       = false # Prevents it from using ~/.kube/config
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
  administrator_login    = local.db_username
  administrator_password = local.db_password
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

# Install cert manager using Helm
resource "helm_release" "cert_manager" {
  count      = local.cloudflare_zone_id == "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0
  name       = "cert-manager"
  namespace  = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.10.0" # Ensure this version is correct for the chart

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true" # Values should be strings in Terraform
  }

  set {
    name  = "global.leaderElection.namespace"
    value = "cert-manager"
  }
  depends_on = [azurerm_kubernetes_cluster.aks]
}

data "http" "nginx_issuer" {
  url = "https://raw.githubusercontent.com/boldbi/boldbi-kubernetes/main/ssl-configuration/nginx-issuer.yaml"
}

# Replace the email placeholder dynamically
locals {
  issuer_yaml = replace(data.http.nginx_issuer.response_body, "<Your_valid_email_address>", local.boldreports_email)
}

# Apply the modified YAML as a kubectl_manifest
resource "kubectl_manifest" "nginx_issuer_apply" {
  count        = local.cloudflare_zone_id == "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0 
  yaml_body    = local.issuer_yaml
  wait         = true
  depends_on   = [helm_release.bold_reports]
}

resource "kubectl_manifest" "patch_ingress" {
  count      = local.cloudflare_zone_id == "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0 
  yaml_body = <<EOT
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: boldreports-ingress
  namespace: bold-services
  annotations:
    cert-manager.io/issuer: "letsencrypt-prod"
EOT
  wait         = true
  #wait_timeout = 300
  depends_on   = [helm_release.bold_reports]
}

########################################################################################
# Install Bold Reports using Helm
resource "helm_release" "bold_reports" {
  name       = "boldreports"
  namespace  = var.boldreports_namespace
  repository = "https://boldreports.github.io/bold-reports-kubernetes"
  chart      = "boldreports"
  version    = var.boldreports_version  # Ensure the version is compatible with your Kubernetes version

  create_namespace = true

  set {
    name  = "namespace"
    value = var.boldreports_namespace
  }

  set {
    name  = "appBaseUrl"
    value = local.app_base_url
  }

  set {
    name  = "image.tag"
    value =  var.boldreports_version
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

  set {
    name  = "databaseServerDetails.dbType"
    value = "postgresql" 
  }

  set {
    name  = "databaseServerDetails.dbHost"
    value =  azurerm_postgresql_flexible_server.postgres.fqdn
  }

  # set {
  #   name  = "databaseServerDetails.dbPort"
  #   value = "5432" 
  # }

  set {
    name  = "databaseServerDetails.dbUser"
    value = local.db_username 
  }

  set {
    name  = "databaseServerDetails.dbPassword"
    value =  local.db_password
  }

  set {
    name  = "databaseServerDetails.dbSchema"
    value = "public" 
  }

  set {
    name  = "rootUserDetails.email"
    value = local.boldreports_email 
  }

  set {
    name  = "rootUserDetails.password"
    value = local.boldreports_password 
  }

  set {
    name  = "licenseKeyDetails.licenseKey"
    value = local.boldreports_unlock_key
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
  count   = local.cloudflare_zone_id != "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0
  zone_id = local.cloudflare_zone_id
  name    = split(".", replace(replace(local.app_base_url , "https://", ""), "http://", ""))[0]
  value   = data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip
  type    = "A"  # A record for an IPv4 address
  ttl     = 300  # You can adjust the TTL as needed
  proxied = false  # Set to true if you want Cloudflare's proxy (e.g., CDN, security features)
}

resource "azurerm_dns_a_record" "nginx_ingress" {
  count               = local.cloudflare_zone_id == "" && var.azure_domain_name != "" && var.azure_domain_rg_name != "" ? 1 : 0
  provider            = azurerm.azure_domain_subscription
  name                = split(".", replace(replace(local.app_base_url , "https://", ""), "http://", ""))[0]
  zone_name           = data.azurerm_dns_zone.azure_zone[count.index].name
  resource_group_name = data.azurerm_dns_zone.azure_zone[count.index].resource_group_name
  ttl                 = 300
  records             = [data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip]
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
  count   = local.cloudflare_zone_id == "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
      az login --service-principal -t ${var.azure_tenant_id} -u ${var.azure_client_id} -p ${var.azure_client_secret}
    EOT
  }
  depends_on = [helm_release.bold_reports]
}

resource "null_resource" "set_subscrition" {
  count   = local.cloudflare_zone_id == "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
      az account set --subscription ${var.azure_sub_id}
    EOT
  }
  depends_on = [null_resource.az_login]
}

resource "null_resource" "update_public_ip_dns" {
  count   = local.cloudflare_zone_id == "" && var.azure_domain_name == "" && var.azure_domain_rg_name == "" ? 1 : 0
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
  count   = local.tls_certificate_path != "" && local.tls_key_path != "" ? 1 : 0
  metadata {
    name      = "bold-tls"
    namespace = "bold-services"
  }

  data = {
    "tls.crt" = file(local.tls_certificate_path)  # Path to the certificate file
    "tls.key" = file(local.tls_key_path) # Path to the private key file
  }
  type = "kubernetes.io/tls"
  depends_on = [helm_release.bold_reports]
}

########################################################################################
# output
output "Output_Massage" {
  value = var.boldreports_secret_vault_name == "" && var.boldreports_secret_vault_rg_name == "" ? "Your app base URL:${local.output_app_base_url}" : "Please use the app-base URL provided in your Azure Key Vault"
}
