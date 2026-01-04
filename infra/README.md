# EKS Infrastructure for Microservice App

Terraform configuration to provision an Amazon EKS cluster for the GameHub microservices application.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Cloud (us-east-1)                                          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  VPC (10.0.0.0/16)                                      │   │
│  │                                                         │   │
│  │  ┌─────────────────┐    ┌─────────────────┐            │   │
│  │  │ Public Subnet   │    │ Public Subnet   │            │   │
│  │  │ (us-east-1a)    │    │ (us-east-1b)    │            │   │
│  │  │ 10.0.101.0/24   │    │ 10.0.102.0/24   │            │   │
│  │  └────────┬────────┘    └─────────────────┘            │   │
│  │           │ NAT Gateway                                 │   │
│  │           ▼                                             │   │
│  │  ┌─────────────────┐    ┌─────────────────┐            │   │
│  │  │ Private Subnet  │    │ Private Subnet  │            │   │
│  │  │ (us-east-1a)    │    │ (us-east-1b)    │            │   │
│  │  │ 10.0.1.0/24     │    │ 10.0.2.0/24     │            │   │
│  │  │                 │    │                 │            │   │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │            │   │
│  │  │  │ EKS Node  │  │    │  │ EKS Node  │  │            │   │
│  │  │  │ t3.small  │  │    │  │ t3.small  │  │            │   │
│  │  │  └───────────┘  │    │  └───────────┘  │            │   │
│  │  └─────────────────┘    └─────────────────┘            │   │
│  │                                                         │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                    EKS Control Plane                            │
│                    (AWS Managed)                                │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  S3 Bucket (Terraform State)                            │   │
│  │  - terraform.tfstate                                    │   │
│  │  - terraform.tfstate.tflock (native locking)            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

**Components:**
- **VPC**: Custom VPC with public and private subnets across 2 AZs
- **EKS Control Plane**: AWS-managed Kubernetes control plane (v1.31)
- **Node Group**: 2 x t3.small worker nodes (managed node group)
- **Networking**: Single NAT Gateway (cost-optimized for dev)
- **State Management**: S3 backend with native locking (no DynamoDB)

## Directory Structure

```
infra/
├── bootstrap/           # One-time setup for state bucket
│   ├── main.tf          # Creates S3 bucket for remote state
│   └── README.md        # Bootstrap instructions
├── backend.tf           # S3 remote state configuration
├── versions.tf          # Terraform and provider versions
├── variables.tf         # Input variable definitions
├── terraform.tfvars     # Variable values
├── vpc.tf               # VPC module configuration
├── eks.tf               # EKS cluster and node groups
├── outputs.tf           # Output values
└── README.md            # This file
```

## Prerequisites

1. **AWS CLI** installed and configured with credentials:
   ```bash
   aws configure
   ```

2. **Terraform** >= 1.10.0 (required for S3 native state locking):
   ```bash
   brew install terraform  # macOS
   terraform version       # verify >= 1.10.0
   ```

3. **kubectl** for interacting with the cluster:
   ```bash
   brew install kubectl  # macOS
   ```

4. **IAM Permissions** - Your AWS user/role needs these permissions:
   - `eks:*` - EKS cluster management
   - `ec2:*` - VPC, subnets, security groups, NAT gateways
   - `iam:*` - IAM roles and policies for EKS
   - `autoscaling:*` - Auto scaling groups for node groups
   - `s3:*` - S3 bucket for Terraform state
   - (Or use `AdministratorAccess` for simplicity in dev)

## Usage

### Step 1: Bootstrap Remote State (One-Time Setup)

First, create the S3 bucket that will store Terraform state:

```bash
cd infra/bootstrap
terraform init
terraform apply
```

This creates:
- S3 bucket with versioning (for state recovery)
- Server-side encryption (AES256)
- Public access blocked
- Deletion protection enabled

### Step 2: Initialize Main Infrastructure

```bash
cd ..  # back to infra/
terraform init
```

This connects to the S3 backend for remote state storage.

### Step 3: Review the Plan

```bash
terraform plan
```

### Step 4: Apply the Configuration

```bash
terraform apply
```

This takes approximately **15-20 minutes** to complete.

### Step 5: Configure kubectl

After the cluster is created, configure kubectl:

```bash
aws eks update-kubeconfig --region us-east-1 --name microservice-app-eks
```

Or use the output:

```bash
$(terraform output -raw configure_kubectl)
```

### Step 6: Verify the Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Remote State & Team Collaboration

This infrastructure uses **S3 remote state with native locking** (Terraform 1.10+):

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Dev A      │     │  Dev B      │     │  CI/CD      │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   S3 Bucket            │
              │   - State file         │
              │   - Lock file (.tflock)│
              │   - Version history    │
              └────────────────────────┘
```

**Benefits:**
- Single source of truth for infrastructure state
- Automatic locking prevents concurrent modifications
- Version history enables state recovery
- No DynamoDB required (uses S3 conditional writes)

## Customization

Edit `terraform.tfvars` to customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `cluster_name` | EKS cluster name | `microservice-app-eks` |
| `kubernetes_version` | K8s version | `1.31` |
| `node_instance_types` | EC2 instance types | `["t3.small"]` |
| `node_desired_size` | Number of nodes | `2` |
| `node_min_size` | Min nodes (scaling) | `1` |
| `node_max_size` | Max nodes (scaling) | `3` |

## Estimated Costs

For `us-east-1` with this configuration (using Spot instances):

| Resource | Cost |
|----------|------|
| EKS Control Plane | ~$0.10/hour ($73/month) |
| 2x t3.small nodes (Spot) | ~$0.006/hour ($9/month) |
| NAT Gateway | ~$0.045/hour + data ($32/month) |
| S3 State Bucket | ~$0.01/month (negligible) |
| **Total** | **~$114/month** |

**Note:** This config uses Spot instances (~70% cheaper than On-Demand). Trade-off: AWS can reclaim nodes with 2-minute warning. Acceptable for dev/test; for production, change `capacity_type` to `"ON_DEMAND"` in eks.tf.

**Further cost reduction:**
- Destroy when not in use: `terraform destroy`
- Use smaller instances: `t3.micro` (limited, but cheaper)

## Outputs

After applying, you'll get:

```bash
terraform output cluster_name        # Cluster name
terraform output cluster_endpoint    # API endpoint
terraform output configure_kubectl   # kubectl config command
terraform output vpc_id              # VPC ID
terraform output private_subnets     # Private subnet IDs
```

## Cleanup

To destroy all resources:

```bash
# Destroy EKS infrastructure
cd infra
terraform destroy

# Optionally destroy the state bucket (if no longer needed)
cd bootstrap
# Remove prevent_destroy lifecycle rule first, then:
terraform destroy
```

**Warning**: This will delete the EKS cluster and all workloads running on it.

## Troubleshooting

### "Error: Failed to get state" or "bucket does not exist"
- Run bootstrap first: `cd bootstrap && terraform init && terraform apply`
- Verify bucket exists: `aws s3 ls | grep terraform-state`

### "Error: state is locked"
- Another terraform process is running - wait for it to complete
- If stale lock, check S3 for `.tflock` file and delete manually (use caution)

### "Error: expected length of name_prefix to be in the range (1 - 38)"
This occurs when node group names are too long. The EKS module appends suffixes like `-eks-node-group-` to create IAM role names, which can exceed AWS's 38-character limit.

```
# Bad - too long when combined with module suffixes
name = "${var.cluster_name}-nodes"  # "my-long-cluster-name-nodes-eks-node-group-" = 45 chars

# Good - keep it short
name = "workers"  # "workers-eks-node-group-" = 23 chars
```

**Fix:** In `eks.tf`, use short node group names like `workers`, `main`, or `spot`.

### "Error: creating EKS Cluster"
- Ensure your AWS credentials have sufficient permissions
- Check if you've reached service quotas for VPCs or EKS clusters

### "Error: timeout waiting for node group"
- Node groups can take 10+ minutes to provision
- Check EC2 instance quotas in your region

### kubectl can't connect
- Run the `configure_kubectl` command from outputs
- Ensure your AWS credentials are valid: `aws sts get-caller-identity`

### Terraform version error
- S3 native locking requires Terraform >= 1.10.0
- Upgrade: `brew upgrade terraform` or download from hashicorp.com

## Known Gotchas

Common pitfalls when working with this infrastructure:

| Gotcha | Description | Solution |
|--------|-------------|----------|
| Long node group names | EKS module appends suffixes that hit AWS 38-char IAM limit | Use short names: `workers`, `main` |
| Spot interruptions | AWS can reclaim Spot instances with 2-min notice | Use `ON_DEMAND` for production |
| Bootstrap order | Can't use S3 backend before bucket exists | Run `bootstrap/` first, then main `infra/` |
| State lock timeout | Stale locks if Terraform crashes | Manually delete `.tflock` file in S3 |
| Provider version drift | Team members on different Terraform versions | Pin versions in `versions.tf` |
