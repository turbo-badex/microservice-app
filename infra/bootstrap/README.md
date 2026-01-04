# Terraform State Bootstrap

This creates the S3 bucket for storing Terraform remote state.

## Why This Exists

**Chicken-and-egg problem**: You can't store Terraform state in an S3 bucket that doesn't exist yet. So:

1. **Bootstrap** (this folder) - Creates the S3 bucket using LOCAL state
2. **Main infra** (parent folder) - Uses that bucket for REMOTE state

## Usage

Run this **once** before using the main infrastructure:

```bash
cd infra/bootstrap

# Initialize and apply
terraform init
terraform apply

# Note the bucket name from the output
```

After the bucket exists, you can use remote state in the main `infra/` folder.

## What Gets Created

- S3 bucket with:
  - Versioning enabled (for state recovery)
  - Server-side encryption (AES256)
  - Public access blocked
  - Deletion protection

## State File Location

The bootstrap state is stored **locally** in this directory (`terraform.tfstate`). This is intentional and safe because:

- It only manages one resource (the S3 bucket)
- The bucket has `prevent_destroy` lifecycle protection
- You rarely need to modify this after initial setup

**Do commit** the bootstrap state to git (it contains no secrets, just bucket metadata).
