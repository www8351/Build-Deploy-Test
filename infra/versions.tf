terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Remote state (state management). Keep commented and pass at init time:
  #   tofu init \
  #     -backend-config="bucket=my-tfstate-bucket" \
  #     -backend-config="key=hardened-web/terraform.tfstate" \
  #     -backend-config="region=us-east-1" \
  #     -backend-config="dynamodb_table=tf-locks"
  # backend "s3" {
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.region
}
