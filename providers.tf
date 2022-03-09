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
