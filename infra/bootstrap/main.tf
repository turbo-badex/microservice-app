# -----------------------------------------------------------------------------
# Bootstrap: S3 Bucket for Terraform Remote State
# -----------------------------------------------------------------------------
# This creates the S3 bucket that will store your Terraform state files.
# Run this ONCE before using remote state in the main infra.
#
# Why separate? Chicken-and-egg problem:
#   - You can't store state in a bucket that doesn't exist yet
#   - So we create the bucket with LOCAL state first
#   - Then the main infra uses this bucket for REMOTE state
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.10.0"  # Required for S3 native locking

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Bootstrap uses LOCAL state (stored in this directory)
  # This is intentional - we can't use remote state for the bucket that
  # will hold our remote state!
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "microservice-app"
      ManagedBy = "terraform-bootstrap"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  type        = string
  default     = "microservice-app-terraform-state"
}

# -----------------------------------------------------------------------------
# S3 Bucket for State Storage
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name

  # Prevent accidental deletion of this bucket
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files for microservice-app"
  }
}

# Enable versioning - critical for state file recovery
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state files at rest (they may contain secrets)
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access - state files should never be public
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.region
}

output "backend_config" {
  description = "Backend configuration to use in main infra"
  value       = <<-EOT

    # Add this to your backend.tf:
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.terraform_state.id}"
        key          = "eks/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}
