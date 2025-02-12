# Provider Configuration
region = "us-east-1"
app_name = "demo"
environment = "env"

# Bold BI Deployment Configuration
bold_services_hosting_environment = "k8s"

# These are the default client libraries used in Bold BI. Update as needed.
install_optional_libs = "mongodb,mysql,influxdb,snowflake,oracle,clickhouse,google"  

# Bold BI requires a site identifier to differentiate sites on the same domain (e.g., http://example.com/bi/site/).  
# Set this to "false" to disable the site identifier. If disabled, each site requires a unique domain.
bold_services_use_site_identifier = "true"  

id_web_image_tag      = "9.1.73"
id_ums_image_tag      = "9.1.73"
id_api_image_tag      = "9.1.73"
bi_web_image_tag      = "9.1.73"
bi_api_image_tag      = "9.1.73"
bi_jobs_image_tag     = "9.1.73"
bi_dataservice_image_tag = "9.1.73"
bold_etl_image_tag    = "9.1.73"

# EC2 Instance and ECS Configuration
launch_type = "EC2"  # Supported values: "EC2" and "FARGATE"
instance_class = "db.t3.xlarge"  # Instance class for RDS or EC2
instance_type = "t3.xlarge"     # EC2 instance type
task_cpu = 512  # CPU allocation for ECS container
task_memory = 1024  # Memory allocation for ECS container (in MiB)
ecs_task_replicas = 1  # Number of ECS task replicas
deployment_maximum_percent = 200  # Maximum percentage of tasks during deployment
deployment_minimum_healthy_percent = 100  # Minimum percentage of healthy tasks during deployment

# AWS secret manager ARN
boldbi_secret_arn = ""
