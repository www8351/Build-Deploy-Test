terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state + locking on SELF-HOSTED infrastructure — no external/unvetted
  # SaaS (data-sovereignty mandate; see SECURITY.md). The `pg` backend stores
  # state in an internal PostgreSQL instance and uses Postgres advisory locks for
  # state locking (no S3 bucket, no DynamoDB, no Terraform Cloud). TLS required.
  #
  # Kept commented so `tofu init -backend=false` validates in CI; activate on the
  # isolated network by uncommenting and passing the conn string at init time
  # (never hard-code credentials — inject from the secrets store / env):
  #   tofu init \
  #     -backend-config="conn_str=postgres://tfstate@tf-state.internal:5432/tfstate?sslmode=require"
  #
  # backend "pg" {
  #   schema_name = "hardened_web"
  # }
}

provider "aws" {
  region = var.region
}
