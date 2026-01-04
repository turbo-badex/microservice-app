# -----------------------------------------------------------------------------
# S3 Backend Configuration with Native State Locking
# -----------------------------------------------------------------------------
# This configures Terraform to store state remotely in S3.
#
# PREREQUISITES:
#   1. Run bootstrap first: cd bootstrap && terraform init && terraform apply
#   2. The S3 bucket must exist before running terraform init here
#
# FEATURES:
#   - Remote state storage (team collaboration)
#   - S3 native locking (no DynamoDB needed - requires Terraform >= 1.10)
#   - Server-side encryption
#   - State versioning (via S3 bucket versioning)
# -----------------------------------------------------------------------------

terraform {
  backend "s3" {
    # Bucket created by bootstrap/main.tf
    bucket = "microservice-app-terraform-state"

    # Path within the bucket - use folders to organize multiple environments
    # Examples:
    #   - "eks/dev/terraform.tfstate"
    #   - "eks/staging/terraform.tfstate"
    #   - "eks/prod/terraform.tfstate"
    key = "eks/terraform.tfstate"

    # Must match the bucket's region
    region = "us-east-1"

    # Encrypt state at rest (state may contain secrets)
    encrypt = true

    # S3 NATIVE LOCKING (New in Terraform 1.10!)
    # Creates a .tflock file in S3 to prevent concurrent modifications
    # No DynamoDB table required anymore!
    use_lockfile = true
  }
}
