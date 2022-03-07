terraform {
  # https://www.terraform.io/language/providers/requirements
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.2"
    }
  }
  required_version = ">= 1.1"
}

locals {
  default_tags = {
    Environment = var.env
    Owner       = "MaiVERIC"
    Project     = "ALPRS"
  }
}

provider "aws" {
  region  = var.aws_provider.region
  profile = var.aws_provider.profile

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags-configuration-block
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/resource-tagging
  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_provider.profile

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias   = "route53"
  profile = "alprscom"

  default_tags {
    tags = local.default_tags
  }
}

data "aws_region" "current" {}
