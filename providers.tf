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

# assumes ALPRSEKSAdminRole
# for EKS cluster creation
provider "aws" {
  alias   = "eks"
  region  = var.aws_provider.region
  profile = var.aws_provider.profile

  assume_role {
    role_arn = aws_iam_role.eks_admin.arn
  }
  default_tags {
    tags = local.default_tags
  }
}
