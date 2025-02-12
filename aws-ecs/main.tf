# Fetching the latest version of the secret from AWS Secrets Manager
data "aws_secretsmanager_secret_version" "boldbi_secret" {
  count     = var.boldbi_secret_arn != "" ? 1 : 0
  secret_id = var.boldbi_secret_arn
}

locals {
  # Decode secrets only if the secret ARN is provided
  secret = length(data.aws_secretsmanager_secret_version.boldbi_secret) > 0 ? jsondecode(data.aws_secretsmanager_secret_version.boldbi_secret[0].secret_string) : {}

  # Use environment variables, secrets, or user-provided inputs
  app_base_url = var.app_base_url != "" ? var.app_base_url : lookup(local.secret, "app_base_url", "")
  db_username       = var.db_username != "" ? var.db_username : lookup(local.secret, "postgresql_username", "")
  db_password       = var.db_password != "" ? var.db_password : lookup(local.secret, "postgresql_password", "")
  bold_unlock_key   = var.bold_unlock_key != "" ? var.bold_unlock_key : lookup(local.secret, "bold_services_unlock_key", "")
  boldbi_username   = var.boldbi_username != "" ? var.boldbi_username : lookup(local.secret, "bold_services_user_email", "")
  boldbi_user_password = var.boldbi_user_password != "" ? var.boldbi_user_password : lookup(local.secret, "bold_services_user_password", "")
  route53_zone_id = var.route53_zone_id != "" ? var.route53_zone_id : lookup(local.secret, "route53_zone_id", "")
  acm_certificate_arn = var.acm_certificate_arn != "" ? var.acm_certificate_arn : lookup(local.secret, "acm_certificate_arn", "")
  
  # Determine protocol dynamically based on app_base_url
  protocol = startswith(local.app_base_url, "https://") ? "https" : "http" 
}

# Define Resource provider.
provider "aws" {
  region = var.region
}

# Fetch available availability zones.
data "aws_availability_zones" "available" {}

# Get the latest ECS-optimized Amazon Linux 2 AMI
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"] # Only fetch images owned by Amazon

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"] # ECS-optimized AMI for x86_64 architecture
    
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Create VPC
resource "aws_vpc" "ecs_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.app_name}-ecs-vpc-${var.environment}"
  }
}
# Create public Subnet
resource "aws_subnet" "ecs_public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.ecs_vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "${var.app_name}-ecs-public-subnet-${var.environment}-${count.index}"
  }
}
# Create an internet gateway
resource "aws_internet_gateway" "ecs_igw" {
  vpc_id = aws_vpc.ecs_vpc.id

  tags = {
    Name = "${var.app_name}-ecs-igw-${var.environment}"
  }
}
# Update the VPC to have a route to the internet gateway
resource "aws_route_table" "ecs_route_table" {
  vpc_id = aws_vpc.ecs_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ecs_igw.id
  }

  tags = {
    Name = "${var.app_name}-ecs-route-table-${var.environment}"
  }
}
# Associate the route table with the public subnets
resource "aws_route_table_association" "ecs_route_table_association" {
  count          = 2
  subnet_id      = aws_subnet.ecs_public_subnet[count.index].id
  route_table_id = aws_route_table.ecs_route_table.id
}
# Create Security Group
resource "aws_security_group" "ecs_sg" {
  vpc_id = aws_vpc.ecs_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      description = "Allow SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"] # Replace with your IP or a range
    }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]  # Allow internal communication within VPC
  }
  
  tags = {
    Name = "${var.app_name}-ecs_sg-${var.environment}"
  }
}
# Create an IAM Role for the PostgreSQL RDS Server
resource "aws_iam_role" "postgresql_rds_role" {
  name = "${var.app_name}-bold-postgresql-rds-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-bold-postgresql-rds-role-${var.environment}"
  }
}

# Restrict PostgreSQL RDS Access to EC2 Instance
resource "aws_security_group" "postgresql_sg" {
  vpc_id = aws_vpc.ecs_vpc.id

  ingress {
    description = "Allow PostgreSQL access from ECS EC2 instances"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_sg.id] # Restrict to ECS EC2 instances
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-postgresql_sg-${var.environment}"
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
  vpc_security_group_ids  = [aws_security_group.postgresql_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.postgresql_subnet_group.name
  skip_final_snapshot     = true

  tags = {
    Name = "${var.app_name}-bold-postgresql-db-${var.environment}"
  }
}

resource "aws_db_subnet_group" "postgresql_subnet_group" {
  name       = "${var.app_name}-postgresql-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.ecs_public_subnet[*].id

  tags = {
    Name = "${var.app_name}-postgresql-subnet-group-${var.environment}"
  }
}

# Create IAM Role.
# IAM Role for ECS Instances
resource "aws_iam_role" "bold_ecs_instance_role" {
  name = "${var.app_name}-bold-ecsInstanceRole-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-bold-ecs-instance-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "bold_ecs_instance_role_policy" {
  role       = aws_iam_role.bold_ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "bold_ecs_instance_profile" {
  name = "${var.app_name}-bold-ecsInstanceProfile-${var.environment}"
  role = aws_iam_role.bold_ecs_instance_role.name
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "bold_ecs_task_execution_role" {
  name = "${var.app_name}-bold-ecsTaskExecutionRole-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.app_name}-bold-ecs-task-execution-role-${var.environment}"
  }
}

resource "aws_iam_role_policy_attachment" "bold_ecs_task_execution_role_policy" {
  role       = aws_iam_role.bold_ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_instance_profile" "bold_ecs_task_execution_instance_profile" {
  name = "${var.app_name}-bold-ecsTaskExecutionInstanceProfile-${var.environment}"
  role = aws_iam_role.bold_ecs_task_execution_role.name
}


# Create ECS Cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.app_name}-ecs-cluster-${var.environment}"
}

# Create Application Load Balancer (ALB)
resource "aws_lb" "ecs_alb" {
  name               = "${var.app_name}-ecs-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = aws_subnet.ecs_public_subnet[*].id
}
# Create a CNAME record in Route 53 to point to the ALB
resource "aws_route53_record" "alb_cname" {
  count = (var.app_base_url != "" && var.route53_zone_id != "") ? 1 : 0
  zone_id = var.route53_zone_id
  name    = replace(replace(var.app_base_url, "https://", ""), "http://", "")
  type    = "CNAME"
  ttl     = 60
  records = [aws_lb.ecs_alb.dns_name]  # Point to the ALB's DNS name
}

# Launch Configuration for ECS EC2 Instances
resource "aws_launch_configuration" "ecs_launch_config" {
  count = var.launch_type == "EC2" ? 1 : 0
  name          = "${var.app_name}-ecs-launch-config-${var.environment}"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.instance_type # Change to t3.xlarge if needed
  iam_instance_profile = aws_iam_instance_profile.bold_ecs_instance_profile.name

  user_data = <<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${aws_ecs_cluster.ecs_cluster.name}" >> /etc/ecs/ecs.config
    yum install -y amazon-efs-utils
    yum install -y nfs-utils
    service docker start
  EOF

  security_groups = [aws_security_group.ecs_sg.id]

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group to Ensure ECS Instances are Available
resource "aws_autoscaling_group" "ecs_asg" {
  count = var.launch_type == "EC2" ? 1 : 0
  desired_capacity     = 1 # Start with 2 instances, adjust as needed
  max_size             = 1
  min_size             = 1
  vpc_zone_identifier  = aws_subnet.ecs_public_subnet[*].id
  #launch_configuration = aws_launch_configuration.ecs_launch_config.id
  launch_configuration = aws_launch_configuration.ecs_launch_config[count.index].id
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
  count          = length(aws_subnet.ecs_public_subnet)
  file_system_id = aws_efs_file_system.app_data_efs.id
  subnet_id      = aws_subnet.ecs_public_subnet[count.index].id
  security_groups = [aws_security_group.ecs_sg.id]
}
# Define ECS Task Definitions for Each Container
resource "aws_ecs_task_definition" "id_web_task" {
  family                   = "${var.app_name}-id-web-task-${var.environment}"
  volume {
    name = "id-web-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([{
    name      = "id-web-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/bold-identity:${var.id_web_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      },
      {
        name  = "APP_BASE_URL"
        value = var.app_base_url != "" ? var.app_base_url : "http://${aws_lb.ecs_alb.dns_name}"
      },
      {
        name  = "INSTALL_OPTIONAL_LIBS"
        value = var.install_optional_libs
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "id-web-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-id_web_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "id_ums_task" {
  family                   = "${var.app_name}-id-ums-task-${var.environment}"
  volume {
    name = "id-ums-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "id-ums-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "id-ums-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/bold-ums:${var.id_ums_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      },
      {
        name  = "BOLD_SERVICES_USE_SITE_IDENTIFIER"
        value = var.bold_services_use_site_identifier
      },
      {
        name  = "BOLD_SERVICES_DB_TYPE"
        value = "postgresql"
      },
      {
        name  = "BOLD_SERVICES_DB_HOST"
        value = aws_db_instance.postgresql.address
      },
      {
        name  = "BOLD_SERVICES_POSTGRESQL_MAINTENANCE_DB"
        value = "postgres"
      },
      {
        name      = "BOLD_SERVICES_DB_USER"
        value = local.db_username
      },
      {
        name      = "BOLD_SERVICES_DB_PASSWORD"
        value = local.db_password
      },
      {
        name      = "BOLD_SERVICES_UNLOCK_KEY"
        value = local.bold_unlock_key
      },
      {
        name      = "BOLD_SERVICES_USER_EMAIL"
        value = local.boldbi_username
      },
      {
        name      = "BOLD_SERVICES_USER_PASSWORD"
        value = local.boldbi_user_password
      }
      # {
      #   name      = "BOLD_SERVICES_DB_NAME"
      #   value = var.postgresql_db_name_arn
      # }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "id-ums-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-id_ums_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "id_api_task" {
  family                   = "${var.app_name}-id-api-task-${var.environment}"
  volume {
    name = "id-api-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "id-api-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "id-api-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/bold-identity-api:${var.id_api_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "id-api-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-id_api_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "bi_web_task" {
  family                   = "${var.app_name}-bi-web-task-${var.environment}"
  volume {
    name = "bi-web-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "bi-web-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "bi-web-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/boldbi-server:${var.bi_web_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "bi-web-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-bi_web_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "bi_api_task" {
  family                   = "${var.app_name}-bi-api-task-${var.environment}"
  volume {
    name = "bi-api-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "bi-api-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "bi-api-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/boldbi-server-api:${var.bi_api_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "bi-api-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-bi_api_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "bi_jobs_task" {
  family                   = "${var.app_name}-bi-jobs-task-${var.environment}"
  volume {
    name = "bi-jobs-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "bi-jobs-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "bi-jobs-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/boldbi-server-jobs:${var.bi_jobs_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "bi-jobs-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-bi_jobs_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "bi_dataservice_task" {
  family                   = "${var.app_name}-bi-dataservice-task-${var.environment}"
  volume {
    name = "bi-dataservice-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "bi-dataservice-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "bi-dataservice-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/boldbi-designer:${var.bi_dataservice_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "bi-dataservice-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-bi_dataservice_task-${var.environment}"
  }
}
resource "aws_ecs_task_definition" "bold_etl_task" {
  family                   = "${var.app_name}-bold-etl-task-${var.environment}"
  volume {
    name = "bold-etl-efs-volume"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.app_data_efs.id
      root_directory = "/"
      transit_encryption = "ENABLED"
    }
  }
  container_definitions    = jsonencode([
    	{
      name      = "init-container"
      image     = "busybox"
      essential = false
      memoryReservation = 128
      command   = [
        "sh", "-c", 
        "if [ ! -f /application/app_data/configuration/config.json ]; then echo 'File not found, waiting for 30 seconds...'; sleep 30; fi"
      ]
      mountPoints = [
        {
          sourceVolume  = "bold-etl-efs-volume"
          containerPath = "/application/app_data"
          readOnly      = false
        }
      ]
    },
    {
    name      = "bold-etl-container"
    image     = "us-docker.pkg.dev/boldbi-294612/boldbi/bold-etl:${var.bold_etl_image_tag}"
    portMappings = [
      {
        containerPort = 80
        hostPort      = var.launch_type == "FARGATE" ? 80 : 0
        protocol      = "tcp"
      }
    ]
    environment = [
      {
        name  = "BOLD_SERVICES_HOSTING_ENVIRONMENT"
        value = var.bold_services_hosting_environment
      }
    ]
    essential = true
    cpu       = var.task_cpu
    memory    = var.task_memory
    mountPoints = [
      {
        sourceVolume  = "bold-etl-efs-volume"
        containerPath = "/application/app_data"
        readOnly      = false
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
       "awslogs-group": "/ecs/logs",
       "mode": "non-blocking",
       "awslogs-create-group": "true",
       "max-buffer-size": "25m",
       "awslogs-region": "us-east-1",
       "awslogs-stream-prefix": "bold"
      }
    }
    dependsOn = [
      {
        containerName = "init-container"
        condition     = "COMPLETE"
      }
    ]
  }])
  execution_role_arn       = aws_iam_role.bold_ecs_task_execution_role.arn
  requires_compatibilities = [var.launch_type]
  network_mode             = var.launch_type == "FARGATE" ? "awsvpc" : "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  tags = {
    Name = "${var.app_name}-bold_etl_task-${var.environment}"
  }
}
# Create EC2 service for each tasks.
resource "aws_ecs_service" "id_web_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-id-web-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.id_web_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.id_web_tg.arn
    container_name   = "id-web-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.id_web_tg]
}
resource "aws_ecs_service" "id_ums_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-id-ums-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.id_ums_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.id_ums_tg.arn
    container_name   = "id-ums-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.id_ums_tg]
}
resource "aws_ecs_service" "id_api_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-id-api-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.id_api_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.id_api_tg.arn
    container_name   = "id-api-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.id_api_tg]
}
resource "aws_ecs_service" "bi_web_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-bi-web-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_web_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_web_tg.arn
    container_name   = "bi-web-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.bi_web_tg]
}
resource "aws_ecs_service" "bi_api_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-bi-api-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_api_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_api_tg.arn
    container_name   = "bi-api-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.bi_api_tg]
}
resource "aws_ecs_service" "bi_jobs_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-bi-jobs-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_jobs_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_jobs_tg.arn
    container_name   = "bi-jobs-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.bi_jobs_tg]
}
resource "aws_ecs_service" "bi_dataservice_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-bi-dataservice-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_dataservice_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_dataservice_tg.arn
    container_name   = "bi-dataservice-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.bi_dataservice_tg]
}
resource "aws_ecs_service" "bold_etl_service_ec2" {
  count = var.launch_type == "EC2" ? 1 : 0
  name            = "${var.app_name}-bold-etl-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bold_etl_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bold_etl_tg.arn
    container_name   = "bold-etl-container"
    container_port   = 80
  }
  depends_on = [aws_lb_target_group.bold_etl_tg]
}
# Create Fargate service for each tasks.
resource "aws_ecs_service" "id_web_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-id-web-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.id_web_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.id_web_tg.arn
    container_name   = "id-web-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.id_web_tg]
}
resource "aws_ecs_service" "id_ums_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-id-ums-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.id_ums_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.id_ums_tg.arn
    container_name   = "id-ums-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.id_ums_tg]
}
resource "aws_ecs_service" "id_api_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-id-api-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.id_api_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.id_api_tg.arn
    container_name   = "id-api-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.id_api_tg]
}
resource "aws_ecs_service" "bi_web_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-bi-web-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_web_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_web_tg.arn
    container_name   = "bi-web-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.bi_web_tg]
}
resource "aws_ecs_service" "bi_api_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-bi-api-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_api_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_api_tg.arn
    container_name   = "bi-api-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.bi_api_tg]
}
resource "aws_ecs_service" "bi_jobs_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-bi-jobs-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_jobs_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_jobs_tg.arn
    container_name   = "bi-jobs-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.bi_jobs_tg]
}
resource "aws_ecs_service" "bi_dataservice_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-bi-dataservice-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bi_dataservice_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bi_dataservice_tg.arn
    container_name   = "bi-dataservice-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.bi_dataservice_tg]
}
resource "aws_ecs_service" "bold_etl_service_fargate" {
  count = var.launch_type == "FARGATE" ? 1 : 0
  name            = "${var.app_name}-bold-etl-service-${var.environment}"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.bold_etl_task.arn
  desired_count   = var.ecs_task_replicas
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent
  launch_type     = var.launch_type

  load_balancer {
    target_group_arn = aws_lb_target_group.bold_etl_tg.arn
    container_name   = "bold-etl-container"
    container_port   = 80
  }
  network_configuration {
    subnets         = aws_subnet.ecs_public_subnet[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
  depends_on = [aws_lb_target_group.bold_etl_tg]
}

# Create Listener for HTTP (80) and HTTPS (443)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "redirect"
    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }

  # default_action {
  #   type             = "fixed-response"
  #   fixed_response {
  #     status_code = "200"
  #     content_type = "text/plain"
  #     message_body = "OK"
  #   }
  # }
  depends_on = [aws_lb.ecs_alb]
}
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = local.acm_certificate_arn

  default_action {
    type             = "fixed-response"
    fixed_response {
      status_code = "200"
      content_type = "text/plain"
      message_body = "OK"
    }
  }
  depends_on = [aws_lb.ecs_alb]
}

# Create Target Groups for Each Service
resource "aws_lb_target_group" "id_web_tg" {
  name        = "${var.app_name}-id-web-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip" 
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "id_ums_tg" {
  name        = "${var.app_name}-id-ums-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "id_api_tg" {
  name        = "${var.app_name}-id-api-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "bi_web_tg" {
  name        = "${var.app_name}-bi-web-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "bi_api_tg" {
  name        = "${var.app_name}-bi-api-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "bi_jobs_tg" {
  name        = "${var.app_name}-bi-jobs-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "bi_dataservice_tg" {
  name        = "${var.app_name}-bi-dataservice-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
resource "aws_lb_target_group" "bold_etl_tg" {
  name        = "${var.app_name}-bold-etl-tg-${var.environment}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.ecs_vpc.id
  target_type = var.launch_type == "EC2" ? "instance" : "ip"
  health_check {
    path                = "/health-check"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}
# Define ALB Path-Based Routing
resource "aws_lb_listener_rule" "bold_etl_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bold_etl_tg.arn
  }

  condition {
    path_pattern {
      values = ["/etlservice/*"]
    }
  }
}
resource "aws_lb_listener_rule" "bi_api_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bi_api_tg.arn
  }

  condition {
    path_pattern {
      values = ["/bi/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "bi_jobs_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bi_jobs_tg.arn
  }

  condition {
    path_pattern {
      values = ["/bi/jobs/*"]
    }
  }
}

resource "aws_lb_listener_rule" "bi_dataservice_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bi_dataservice_tg.arn
  }

  condition {
    path_pattern {
      values = ["/bi/designer/*"]
    }
  }
}

resource "aws_lb_listener_rule" "bi_web_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bi_web_tg.arn
  }

  condition {
    path_pattern {
      values = ["/bi/*"]
    }
  }
}

resource "aws_lb_listener_rule" "id_api_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 60

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.id_api_tg.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "id_ums_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 70

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.id_ums_tg.arn
  }

  condition {
    path_pattern {
      values = ["/ums/*"]
    }
  }
}

resource "aws_lb_listener_rule" "id_web_rule" {
  listener_arn = local.protocol == "https" ? aws_lb_listener.https.arn : aws_lb_listener.http.arn
  priority     = 80

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.id_web_tg.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# Outputs
output "ecs_cluster_name" {
  value = aws_ecs_cluster.ecs_cluster.name
}
output "ecs_optimized_ami_id" {
  value = data.aws_ami.ecs_optimized.id
}
output "alb_dns_name" {
  value = aws_lb.ecs_alb.dns_name
}

output "app_base_url" {
  value = var.app_base_url
}
