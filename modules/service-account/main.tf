# https://developer.hashicorp.com/terraform/language/providers/configuration
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

locals {
  oidc_id = replace(var.oidc_provider_arn, "/^.+:oidc-provider\\//", "")
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "oidc_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_id}:sub"
      values   = ["system:serviceaccount:${var.service_account.namespace}:${var.service_account.name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_id}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "k8s_sa" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.oidc_trust.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "k8s_sa" {
  for_each = { for arn in var.policy_arns : basename(arn) => arn }

  role       = aws_iam_role.k8s_sa.id
  policy_arn = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
resource "aws_iam_role_policy" "k8s_sa" {
  for_each = var.policy_docs

  name   = each.key
  role   = aws_iam_role.k8s_sa.id
  policy = each.value
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_account_v1
resource "kubernetes_service_account_v1" "k8s_sa" {
  metadata {
    name      = var.service_account.name
    namespace = var.service_account.namespace
    labels    = var.service_account.labels
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.k8s_sa.arn
    }
  }
}
