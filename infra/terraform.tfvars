# -----------------------------------------------------------------------------
# EKS Cluster Configuration for GameHub Microservices
# -----------------------------------------------------------------------------

# AWS Configuration
aws_region   = "us-east-1"
cluster_name = "microservice-app-eks"
environment  = "dev"

# VPC Configuration
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b"]
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]

# EKS Configuration
kubernetes_version = "1.31"

# Node Group Configuration - Small cluster for microservices
node_instance_types = ["t3.small"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 3
node_disk_size      = 20

# Access Configuration
enable_public_access  = true
enable_private_access = true
