terraform {
  required_providers {
      cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }
}

# Fetching the latest version of the secret from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "boldreports_secret" {
  count     = var.boldreports_secret_arn != "" ? 1 : 0
  secret_id = var.boldreports_secret_arn
}

locals {
    # Decode secrets only if the secret ARN is provided
    secret = length(data.aws_secretsmanager_secret_version.boldreports_secret) > 0 ? jsondecode(data.aws_secretsmanager_secret_version.boldreports_secret[0].secret_string) : {}
    # Use environment variables, secrets, or user-provided inputs
    app_base_url      = var.app_base_url != "" ? var.app_base_url : lookup(local.secret, "app_base_url", "")
    db_username       = var.db_username != "" ? var.db_username : lookup(local.secret, "db_username", "")
    db_password       = var.db_password != "" ? var.db_password : lookup(local.secret, "db_password", "")
    boldreports_unlock_key = var.boldreports_unlock_key != "" ? var.boldreports_unlock_key : lookup(local.secret, "boldreports_unlock_key", "")
    boldreports_email      = var.boldreports_email != "" ? var.boldreports_email : lookup(local.secret, "boldreports_email", "")
    boldreports_password   = var.boldreports_password != "" ? var.boldreports_password : lookup(local.secret, "boldreports_password", "")
    route53_zone_id   = var.route53_zone_id != "" ? var.route53_zone_id : lookup(local.secret, "route53_zone_id", "")
    tls_certificate_path = var.tls_certificate_path != "" ? var.tls_certificate_path : lookup(local.secret, "tls_certificate_path", "")
    tls_key_path         = var.tls_key_path != "" ? var.tls_key_path : lookup(local.secret, "tls_key_path", "")
    cloudflare_api_token = var.cloudflare_api_token != "" ? var.cloudflare_api_token : lookup(local.secret, "cloudflare_api_token", "")
    cloudflare_zone_id   = var.cloudflare_zone_id != "" ?  var.cloudflare_zone_id : lookup(local.secret, "cloudflare_zone_id", "")

    # Determine protocol dynamically based on app_base_url
    protocol = startswith(local.app_base_url, "https://") ? "https" : "http" 
}

# Configure the AWS provider
provider "aws" {
  region = var.region
}

# Cloudflare provider setup
provider "cloudflare" {
  api_token = local.cloudflare_api_token != "" ? local.cloudflare_api_token : "dummytokenplaceholdedummytokenplaceholde"
}

# Configure the Kubernetes provider with an alias
provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_cluster_auth.token
}

# Configure the Helm provider using the aliased Kubernetes provider
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks_cluster_auth.token
  }
}

# Fetch available availability zones.
data "aws_availability_zones" "available" {}

# Create VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.app_name}-eks-vpc-${var.environment}"
  }
}

# Create public Subnet
resource "aws_subnet" "eks_public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.app_name}-eks-public-subnet-${var.environment}-${count.index}"
  }
}

# Create an internet gateway
resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "${var.app_name}-eks-igw-${var.environment}"
  }
}

# Update the VPC to have a route to the internet gateway
resource "aws_route_table" "eks_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "${var.app_name}-eks-route-table-${var.environment}"
  }
}

# Associate the route table with the public subnets
resource "aws_route_table_association" "eks_route_table_association" {
  count          = 2
  subnet_id      = aws_subnet.eks_public_subnet[count.index].id
  route_table_id = aws_route_table.eks_route_table.id
  depends_on = [aws_internet_gateway.eks_igw]
}

# Create Security Group
resource "aws_security_group" "eks_sg" {
  vpc_id = aws_vpc.eks_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (80)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS (443)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH (Only if needed)
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict this in production
  }

  # Allow all internal communication within the VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow PostgreSQL (5432) within the VPC
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow EFS (2049) within the VPC
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "${var.app_name}-eks_sg-${var.environment}"
  }
}

resource "aws_db_subnet_group" "postgresql_subnet_group" {
  name       = "${var.app_name}-postgresql-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.eks_public_subnet[*].id

  tags = {
    Name = "${var.app_name}-postgresql-subnet-group-${var.environment}"
  }
}

# Create PostgreSQL RDS Server.
resource "aws_db_instance" "postgresql" {
  #db_name                 = local.db_name
  identifier              = "${var.app_name}-postgresql-db-${var.environment}"
  engine                  = "postgres"
  instance_class          = var.instance_class
  allocated_storage       = 20
  username                = local.db_username
  password                = local.db_password
  publicly_accessible     = false
  vpc_security_group_ids  = [aws_security_group.eks_sg.id] # Use EKS SG
  db_subnet_group_name    = aws_db_subnet_group.postgresql_subnet_group.name
  skip_final_snapshot     = true
  tags = {
    Name = "${var.app_name}-bold-postgresql-db-${var.environment}"
  }
  depends_on = [ aws_db_subnet_group.postgresql_subnet_group,aws_security_group.eks_sg ]
}

# Create EFS FileSystem
resource "aws_efs_file_system" "app_data_efs" {
  creation_token = "${var.app_name}-app-data-efs-${var.environment}"
  encrypted = true
  tags = {
    Name = "${var.app_name}-app-data-efs-${var.environment}"
  }
  
}

# Create EFS mount target
resource "aws_efs_mount_target" "app_data_efs_mount_target" {
  count          = length(aws_subnet.eks_public_subnet)
  file_system_id = aws_efs_file_system.app_data_efs.id
  subnet_id      = aws_subnet.eks_public_subnet[count.index].id
  security_groups = [aws_security_group.eks_sg.id]
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.app_name}-eks-cluster-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Create EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.app_name}-eks-cluster-${var.environment}"
  role_arn = aws_iam_role.eks_cluster_role.arn
  
  vpc_config {
    subnet_ids = aws_subnet.eks_public_subnet[*].id
    security_group_ids = [aws_security_group.eks_sg.id]  # ✅ Attach Security Group
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

resource "aws_iam_role" "eks_node_role" {
  name = "${var.app_name}-eks-node-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "boldreports-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids = [for subnet in aws_subnet.eks_public_subnet : subnet.id] # Replace with your subnet IDs
  instance_types  = [var.node_instance_type]
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  depends_on = [ aws_eks_cluster.eks_cluster ]
}

# Fetch EKS cluster details
data "aws_eks_cluster" "eks_cluster" {
  name = aws_eks_cluster.eks_cluster.name
}

# Fetch EKS cluster authentication token
data "aws_eks_cluster_auth" "eks_cluster_auth" {
  name = aws_eks_cluster.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
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

  depends_on = [aws_eks_cluster.eks_cluster, aws_eks_node_group.eks_nodes]
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

resource "time_sleep" "wait_for_nginx_ingress" {
  create_duration = "300s" # Wait for 5 minutes
  depends_on      = [data.kubernetes_service.nginx_ingress_service]
}

#Create a CNAME record in Route 53 to point to the Nginx Loadbalancer External IP
resource "aws_route53_record" "alb_cname" {
  count = (local.app_base_url!= "" && local.route53_zone_id != "") ? 1 : 0
  zone_id = local.route53_zone_id
  # Extract the subdomain only (remove https://, http://, and the main domain part)
  name = regex("^([^.]+)", replace(replace(local.app_base_url, "https://", ""), "http://", ""))[0]
  type    = "CNAME"
  ttl     = 60
  records = [data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].hostname]
  depends_on = [helm_release.nginx_ingress,time_sleep.wait_for_nginx_service]
}

resource "cloudflare_record" "alb_cname" {
  count   = local.app_base_url!= "" && local.cloudflare_zone_id != "" && local.route53_zone_id == "" ? 1 : 0
  zone_id = local.cloudflare_zone_id
  name    = regex("^([^.]+)", replace(replace(var.app_base_url, "https://", ""), "http://", ""))[0]
  value   = data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].hostname
  type    = "CNAME" # A record for an IPv4 address
  ttl     = 300  # You can adjust the TTL as needed
  proxied = false  # Set to true if you want Cloudflare's proxy (e.g., CDN, security features)
  depends_on = [helm_release.nginx_ingress,time_sleep.wait_for_nginx_service]
}

resource "helm_release" "aws_efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  
  # Ensure the namespace exists
  create_namespace = false

  # Any additional Helm values can be set here
  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

  depends_on = [aws_eks_cluster.eks_cluster]  # Ensure the EKS cluster exists before installing
}

# Create Bold TLS Secret
resource "kubernetes_secret" "bold_tls" {
  count   = local.tls_certificate_path != "" && local.tls_key_path != "" ? 1 : 0
  metadata {
    name      = "bold-tls"
    namespace = var.boldreports_namespace
  }

  data = {
    "tls.crt" = file(local.tls_certificate_path)  # Path to the certificate file
    "tls.key" = file(local.tls_key_path) # Path to the private key file
  }
  type = "kubernetes.io/tls"
  depends_on = [helm_release.bold_reports]
}

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
    value = local.app_base_url != "" ? local.app_base_url : "http://${data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].hostname}"
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
    value = "eks" 
  }

  set {
    name  = "persistentVolume.eks.efsFileSystemId"
    value = aws_efs_file_system.app_data_efs.id
  }

  set {
    name  = "databaseServerDetails.dbType"
    value = "postgresql" 
  }

  set {
    name  = "databaseServerDetails.dbHost"
    value =  aws_db_instance.postgresql.address
  }

  set {
    name  = "databaseServerDetails.dbPort"
    value = "5432" 
  }

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
    
  ]
}


output "alb_cname_record" {
  value       = aws_route53_record.alb_cname[*].name
  description = "The CNAME record created in Route 53"
}

# Outputs
output "eks_cluster_name" {
  value = aws_eks_cluster.eks_cluster.name
}

output "app_base_url" {
  value = local.app_base_url
}

output "domain" {
  value = "http://${data.kubernetes_service.nginx_ingress_service.status[0].load_balancer[0].ingress[0].hostname}"
}