# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "backend_config" {
  program = [
    "${path.module}/shared/tfvars.sh",
    "${path.module}/config/${var.env}.conf",
  ]
}

# local.xxx_bucket variables are defined in variables.tf
# to accept overrides from var.xxx_bucket with var.env a
# part of the default bucket names.
locals {
  buckets = {
    webapp = local.webapp_bucket
    config = local.config_bucket
    audit  = local.audit_bucket
    media  = local.media_bucket
    sftp   = local.sftp_bucket
  }
  user_data_bucket = data.external.backend_config.result.bucket
  user_data_s3_url = "s3://${local.user_data_bucket}/userdata"
}

# also use the Terraform state bucket to store instance
# initialization scripts that are too big for user data
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/s3_bucket
data "aws_s3_bucket" "user_data" {
  bucket = local.user_data_bucket
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets
  # in provider region
  bucket = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = local.buckets
  bucket   = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = local.buckets
  bucket   = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration
resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.buckets["audit"].id

  rule {
    id     = "audit"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "https_only" {
  for_each = local.buckets

  statement {
    sid     = "OnlyAllowAccessViaTLS"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.buckets[each.key].arn,
      "${aws_s3_bucket.buckets[each.key].arn}/*",
    ]
    principals {
      identifiers = ["*"]
      type        = "*"
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = [false]
    }
  }
}

data "aws_iam_policy_document" "webapp_oai" {
  source_policy_documents = [data.aws_iam_policy_document.https_only["webapp"].json]

  statement {
    sid       = "AllowCloudFrontAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.buckets["webapp"].arn}/*"]

    principals {
      identifiers = [aws_cloudfront_origin_access_identity.webapp.iam_arn]
      type        = "AWS"
    }
  }
}

locals {
  bucket_policies = {
    webapp = data.aws_iam_policy_document.webapp_oai
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
resource "aws_s3_bucket_policy" "buckets" {
  for_each = local.buckets

  bucket = each.value
  policy = lookup(local.bucket_policies, each.key,
    data.aws_iam_policy_document.https_only[each.key]
  ).json
}
