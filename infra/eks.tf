# -----------------------------------------------------------------------------
# EKS Cluster Module - Creates managed Kubernetes cluster
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # VPC Configuration
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Cluster Access Configuration
  cluster_endpoint_public_access  = var.enable_public_access
  cluster_endpoint_private_access = var.enable_private_access

  # Grant the current IAM user/role admin permissions
  enable_cluster_creator_admin_permissions = true

  # EKS Addons - Essential components for cluster operation
  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
      
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
  }

  # EKS Managed Node Group - Worker nodes for your workloads
  eks_managed_node_groups = {
    main = {
      # Keep name short - EKS module appends suffixes that hit AWS 38-char limit
      name = "workers"

      # Instance configuration
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = "SPOT"

      # Scaling configuration
      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Disk configuration
      disk_size = var.node_disk_size

      # Node labels for workload scheduling
      labels = {
        role        = "general"
        environment = var.environment
      }

      # Update configuration
      update_config = {
        max_unavailable_percentage = 50
      }

      tags = {
        Name        = "${var.cluster_name}-node"
        Environment = var.environment
      }
    }
  }

  # Cluster tags
  tags = {
    Name        = var.cluster_name
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# Security Group Rules - Allow node-to-node communication
# -----------------------------------------------------------------------------

resource "aws_security_group_rule" "node_to_node" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = module.eks.node_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}
