terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.2"
    }
  }
  required_version = ">= 1.1"
}

provider "aws" {
  profile = var.aws_provider.profile
  region  = var.aws_provider.region

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags-configuration-block
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/resource-tagging
  default_tags {
    tags = {
      Environment = var.env
      Owner       = "MaiVERIC"
      Project     = "ALPRS"
    }
  }
}
