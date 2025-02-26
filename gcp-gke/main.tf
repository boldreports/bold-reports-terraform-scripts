# Provider Configuration
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  credentials = file(var.google_credentials_json)
  project     = var.gcp_project_id
  region      = var.gcp_region
}

# Cloudflare provider setup
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Data source to fetch the default Google client config
data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = google_container_cluster.gke_cluster.endpoint
    cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth.0.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.gke_cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate)
}

# Create VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "${var.app_name}-vpc-${var.environment}"
  auto_create_subnetworks = false
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.app_name}-subnet-${var.environment}"
  ip_cidr_range = var.subnet_cidr_range
  region        = var.gcp_region
  network       = google_compute_network.vpc_network.id
  private_ip_google_access = true  # Allow GCP services (e.g., Cloud SQL) access without internet

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Firewall Rule: Allow Internal Traffic
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.app_name}-allow-internal-${var.environment}"
  network = google_compute_network.vpc_network.id

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "5432"]
  }

  source_ranges = ["10.0.0.0/16"]  # Restrict traffic to internal networks only
}

# Firewall Rule: Deny All Incoming Traffic by Default
resource "google_compute_firewall" "deny_all" {
  name    = "${var.app_name}-deny-all-ingress-${var.environment}"
  network = google_compute_network.vpc_network.id

  deny {
    protocol = "all"
  }

  source_ranges = [var.subnet_cidr_range]  # Dynamically use the user-provided subnet CIDR
  priority      = 1000
}

# Cloud NAT Router
resource "google_compute_router" "nat_router" {
  name    = "nat-router-${var.environment}"
  network = google_compute_network.vpc_network.id
  region  = var.gcp_region
}

# Cloud NAT Configuration
resource "google_compute_router_nat" "cloud_nat" {
  name   = "cloud-nat-${var.environment}"
  router = google_compute_router.nat_router.name
  region = google_compute_router.nat_router.region

  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Fetch available zones for the given region
data "google_compute_zones" "available_zones" {
  region = var.gcp_region
}

# Create Cloud Filestore Instance
resource "google_filestore_instance" "filestore" {
  name     = "${var.app_name}-filestore-${var.environment}"
  location = data.google_compute_zones.available_zones.names[0]
  tier     = "BASIC_HDD"  # Options: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD, ENTERPRISE
  
  file_shares {
    capacity_gb = 1024  # 1TB capacity, adjust as needed
    name        = "boldreports_data"
  }

  networks {
    network         = google_compute_network.vpc_network.id
    modes           = ["MODE_IPV4"]
  }

  lifecycle {
    ignore_changes = [networks]
  }
}

# Allocate an IP range for Google services
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16  # Adjust as needed
  network       = google_compute_network.vpc_network.id
}

# Create a Private Services Access connection
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  
  # Ignore changes to avoid modification conflicts
  lifecycle {
    ignore_changes = [reserved_peering_ranges]
  }
}

# Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "postgres_instance" {
  name             = "${var.app_name}-postgres-${var.environment}"
  database_version = "POSTGRES_15"  # Adjust as needed
  region           = var.gcp_region

  settings {
    tier = var.postgres_instance  # Change based on your workload

    ip_configuration {
      ipv4_enabled = false  # Enables Public IP access
      private_network = google_compute_network.vpc_network.id  # Connect Cloud SQL to the VPC
    }

    backup_configuration {
      enabled = true
    }
  }
  deletion_protection = false  # ✅ Set to false to allow deletion
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# PostgreSQL User
resource "google_sql_user" "db_user" {
  name     = var.db_username
  instance = google_sql_database_instance.postgres_instance.name
  password = var.db_password
  depends_on = [google_sql_database_instance.postgres_instance]
}

# Create PostgreSQL Database
resource "google_sql_database" "bold_services_db" {
  name     = "bold_reports"
  instance = google_sql_database_instance.postgres_instance.name
  depends_on = [google_sql_user.db_user]
}



# GKE Cluster Configuration
resource "google_container_cluster" "gke_cluster" {
  name     = "${var.app_name}-gke-cluster-${var.environment}"
  location = var.gcp_region

  initial_node_count = 1  # Number of nodes in the cluster

  # Network and subnetwork configuration
  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnet.name

  # Set deletion protection to false to allow cluster deletion
  deletion_protection = false
  
  # Enable private cluster (no external IPs for nodes)
  private_cluster_config {
    enable_private_nodes = true
  }

  # Enable IAM for service accounts
  enable_legacy_abac = false

  # Master authorized networks configuration
  master_authorized_networks_config {
    cidr_blocks {
        cidr_block   = "49.204.142.100/32"  # First allowed IP range
        display_name = "Network 1"
    }

    cidr_blocks {
        cidr_block   = "182.156.201.226/32"  # Second allowed IP range (single IP)
        display_name = "Network 2"
    }
  }

  # Remove the default node pool after cluster creation
  remove_default_node_pool = true
}

# Node pool configuration
resource "google_container_node_pool" "gke_node_pool" {
  name       = "${var.app_name}-node-pool"
  cluster    = google_container_cluster.gke_cluster.name
  location   = var.gcp_region
  node_count = var.gke_initial_node_count  # Initial number of nodes

  node_config {
    machine_type = var.gke_machine_type  # VM type for your nodes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  management {
    auto_repair = true  # Automatically repair nodes
    auto_upgrade = true  # Automatically upgrade nodes
  }

  # Enable Cluster Autoscaler
  autoscaling {
    min_node_count = var.gke_min_node_count  # Minimum number of nodes
    max_node_count = var.gke_max_node_count  # Maximum number of nodes
  }
}

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

  depends_on = [google_container_cluster.gke_cluster]
}

# Fetch the status of the Kubernetes service created by the Helm release
resource "time_sleep" "wait_for_nginx_service" {
  depends_on = [helm_release.nginx_ingress]

  create_duration = "30s"
}

data "kubernetes_service" "nginx_ingress_service" {
  metadata {
    name      = "nginx-ingress-ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
  depends_on = [time_sleep.wait_for_nginx_service]
}

# Create Bold TLS Secret
resource "kubernetes_secret" "bold_tls" {
  count   = var.tls_certificate_path != "" && var.tls_key_path != "" ? 1 : 0
  metadata {
    name      = "bold-tls"
    namespace = var.boldreports_namespace
  }

  data = {
    "tls.crt" = file(var.tls_certificate_path)  # Path to the certificate file
    "tls.key" = file(var.tls_key_path) # Path to the private key file
  }
  type = "kubernetes.io/tls"
  depends_on = [helm_release.boldreports]
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

# Install Bold BI using Helm
resource "helm_release" "boldreports" {
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
    value = var.app_base_url != "" ? var.app_base_url : "http://${data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].ip}"
  }

  set {
    name  = "image.tag"
    value =  var.boldreports_version
  }
  set {
    name  = "loadBalancer.type"
    value = "nginx"
  }
  set {
    name  = "clusterProvider"
    value = "gke" 
  }

  set {
    name  = "persistentVolume.gke.fileShareName"
    value = google_filestore_instance.filestore.file_shares[0].name
  }
  set {
    name  = "persistentVolume.gke.fileShareIp"
    value = google_filestore_instance.filestore.networks[0].ip_addresses[0]
  }

  set {
    name  = "databaseServerDetails.dbType"
    value = "postgresql" 
  }

  set {
    name  = "databaseServerDetails.dbHost"
    value = google_sql_database_instance.postgres_instance.ip_address[0].ip_address
  }

  set {
    name  = "databaseServerDetails.dbPort"
    value = "5432" 
  }

  set {
    name  = "databaseServerDetails.dbUser"
    value = var.db_username
  }

  set {
    name  = "databaseServerDetails.dbPassword"
    value =  var.db_password
  }

  set {
    name  = "databaseServerDetails.dbName"
    value =  google_sql_database.bold_services_db.name
  }

  set {
    name  = "databaseServerDetails.dbSchema"
    value = "public" 
  }

  set {
    name  = "rootUserDetails.email"
    value = var.boldreports_email
  }

  set {
    name  = "rootUserDetails.password"
    value = var.boldreports_password
  }

  set {
    name  = "licenseKeyDetails.licenseKey"
    value = var.boldreports_unlock_key
  }
  depends_on = [
    
  ]
}

# Outputs
output "boldreports_access_message" {
  value = "Access the following URL in your browser to use Bold Reports: ${var.app_base_url}"
}

# resource "google_compute_network_peering" "gke_vpc_peering" {
#   name         = "servicenetworking-googleapis-com"
#   network      = "projects/${var.gcp_project_id}/global/networks/${var.app_name}-vpc-${var.environment}"
#   peer_network = "projects/${var.gcp_project_id}/global/networks/servicenetworking-googleapis-com"
 
#   import_custom_routes = true
# }
