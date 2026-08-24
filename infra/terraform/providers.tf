terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Local state by design: infra is applied by hand from your PC, not by
  # Jenkins, so a stray CI job can never run `terraform apply`/`destroy`
  # against this cluster. Once more than one person touches this, switch to
  # a remote backend so state isn't only on one laptop:
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "smartdockershrinker/eks/terraform.tfstate"
  #   region         = "eu-central-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
