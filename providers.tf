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

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  host                   = local.eks.endpoint
  cluster_ca_certificate = local.eks.ca_cert

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", local.eks.name,
      "--role-arn", aws_iam_role.eks_admin.arn,
      "--profile", var.aws_provider.profile,
      "--region", var.aws_provider.region,
    ]
  }
}

# this alternate provider connects to the same EKS cluster but
# requires manual addition of the cluster with renamed context
provider "kubernetes" {
  alias          = "alternate"
  config_path    = "~/.kube/config"
  config_context = "alprs${var.env}"
}

# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes {
    host                   = local.eks.endpoint
    cluster_ca_certificate = local.eks.ca_cert

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", local.eks.name,
        "--role-arn", aws_iam_role.eks_admin.arn,
        "--profile", var.aws_provider.profile,
        "--region", var.aws_provider.region,
      ]
    }
  }
}
