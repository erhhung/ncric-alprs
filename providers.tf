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
}
