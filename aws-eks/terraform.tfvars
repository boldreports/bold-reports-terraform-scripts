# Provider Configuration
region = "us-east-1"
app_name = "reports"
environment = "dev"
vpc_cidr = "10.0.0.0/16"

# These are the default client libraries used in Bold Reports. Update as needed.
install_optional_libs = "mongodb,mysql,influxdb,snowflake,oracle,clickhouse,google"  

node_instance_type = "t3.xlarge"

boldreports_version = "13.1.26"

instance_class = "db.t3.micro"
# AWS secret manager ARN
boldreports_secret_arn = ""

# Update preferred Load Balancer(nginx OR traefik)
load_balancer_type = "traefik" # nginx OR traefik