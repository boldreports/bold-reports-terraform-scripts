# Provider Variable
variable "google_credentials_json" {
  description = "Path to Google Cloud credentials JSON file"
  type        = string
  sensitive   = true
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region for resources"
  type        = string
}

# Resource Name and Configuration
variable "app_name" {
  description = "Application name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g., dev, prod)"
  type        = string
}

variable "subnet_cidr_range" {
  description = "CIDR range for the subnet"
  type        = string
}

variable "gke_initial_node_count" {
  description = "Initial node count for GKE cluster"
  type        = number
}

variable "gke_min_node_count" {
  description = "Minimum node count for autoscaling GKE cluster"
  type        = number
}

variable "gke_max_node_count" {
  description = "Maximum node count for autoscaling GKE cluster"
  type        = number
}

variable "gke_machine_type" {
  description = "Instance type of GKE node"
  type        = string
  default     = "e2-standard-2"
}

variable "gke_disk_size_gb" {
  description = "Disk size for GKE nodes in GB"
  type        = number
}

# PostgreSQL Configuration
variable "postgres_instance" {
  description = "Instance type for PostgreSQL server"
  type        = string
  default     = "db-g1-small"
}

variable "db_username" {
  description = "The PostgreSQL username"
  type        = string
  nullable    = false
}

variable "db_password" {
  description = "The PostgreSQL password"
  type        = string
  sensitive   = true
  nullable    = false
}

# Bold BI Application Variables
variable "boldreports_namespace" {
  description = "Bold BI deployment namespace"
  type        = string
  default     = "bold-services"
}

variable "boldreports_version" {
  type        = string
  description = "Bold BI Version"
}

variable "app_base_url" {
  description = "The base URL for the Bold BI application (e.g., https://example.com). If left empty, the script will use the ALB load balancer DNS for application hosting."
  type        = string
}

variable "install_optional_libs" {
  description = "Comma-separated list of optional libraries for Bold BI"
  type        = string
  default     = "mongodb,mysql,influxdb,snowflake,oracle,clickhouse,google"
}

variable "boldreports_unlock_key" {
  description = "The Bold services unlock key"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "boldreports_email" {
  description = "The Bold BI admin username"
  type        = string
  nullable    = false
}

variable "boldreports_password" {
  description = "The Bold BI admin password"
  type        = string
  sensitive   = true
  nullable    = false
}

# Cloudflare Provider
variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
  default     = ""
}

# SSL Certificate Paths
variable "tls_certificate_path" {
  description = "The path to the TLS certificate file"
  type        = string
  default     = ""
}

variable "tls_key_path" {
  description = "The path to the TLS private key file"
  type        = string
  default     = ""
}