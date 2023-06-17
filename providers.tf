# https://registry.terraform.io/providers/hashicorp/aws/latest/docs
provider "aws" {
  region  = var.aws_provider.region
  profile = var.aws_provider.profile

  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags-configuration-block
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/resource-tagging
  default_tags {
    tags = local.default_tags
  }
}

# CloudFront is unavailable
# in AWS GovCloud accounts
provider "aws" {
  alias   = "cloudfront"
  region  = "us-east-1"
  profile = "alprscom"

  default_tags {
    tags = local.default_tags
  }
}

# both dev and prod zones
# are in the dev account
provider "aws" {
  alias   = "route53"
  profile = "alprscom"

  default_tags {
    tags = local.default_tags
  }
}
