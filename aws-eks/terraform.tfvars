# Provider Configuration
region = "us-east-1"
app_name = "test"
environment = "repo"
vpc_cidr = "10.0.0.0/16"

# These are the default client libraries used in Bold Reports. Update as needed.
install_optional_libs = "mongodb,mysql,influxdb,snowflake,oracle,clickhouse,google"  

node_instance_type = "t3.xlarge"

boldreports_version = "8.1.1"

instance_class = "db.t3.micro"
# AWS secret manager ARN
boldreports_secret_arn = ""
