# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "backend_config" {
  program = [
    "${path.module}/shared/tfvars.sh",
    "${path.module}/config/${var.env}.conf",
  ]
}

locals {
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
  for_each = var.buckets
  # in provider region
  bucket = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each   = var.buckets
  depends_on = [aws_s3_bucket.buckets]
  bucket     = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each   = var.buckets
  depends_on = [aws_s3_bucket.buckets]
  bucket     = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls
resource "aws_s3_bucket_ownership_controls" "buckets" {
  for_each   = var.buckets
  depends_on = [aws_s3_bucket.buckets]
  bucket     = each.value

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl
resource "aws_s3_bucket_acl" "buckets" {
  for_each   = var.buckets
  depends_on = [aws_s3_bucket.buckets]
  bucket     = each.value

  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/acl-overview.html#canned-acl
  acl = each.key == "audit" ? "log-delivery-write" : "private"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.buckets["backup"].id

  rule {
    id     = "backup"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

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

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging
resource "aws_s3_bucket_logging" "sftp" {
  bucket = aws_s3_bucket.buckets["sftp"].id

  target_bucket = aws_s3_bucket.buckets["audit"].id
  target_prefix = "AWSLogs/${local.account}/transfer/"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "https_only" {
  for_each = var.buckets

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

data "aws_iam_policy_document" "elb_logs" {
  source_policy_documents = [data.aws_iam_policy_document.https_only["audit"].json]

  # https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/enable-access-logs.html
  statement {
    sid       = "AllowELBAccountPutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.buckets["audit"].arn}/AWSLogs/${local.account}/*"]

    principals {
      identifiers = ["arn:aws:iam::${var.elb_account_id}:root"]
      type        = "AWS"
    }
  }
  statement {
    sid       = "AllowLogDeliveryPutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.buckets["audit"].arn}/AWSLogs/${local.account}/*"]

    principals {
      identifiers = ["delivery.logs.amazonaws.com"]
      type        = "Service"
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  statement {
    sid       = "AllowLogDeliveryGetBucketAcl"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.buckets["audit"].arn]

    principals {
      identifiers = ["delivery.logs.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "app_oai" {
  source_policy_documents = [data.aws_iam_policy_document.https_only["webapp"].json]

  statement {
    sid       = "AllowCloudFrontAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.buckets["webapp"].arn}/*"]

    principals {
      identifiers = [aws_cloudfront_origin_access_identity.app.iam_arn]
      type        = "AWS"
    }
  }
}

locals {
  bucket_policies = {
    audit  = data.aws_iam_policy_document.elb_logs
    webapp = data.aws_iam_policy_document.app_oai
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
resource "aws_s3_bucket_policy" "buckets" {
  for_each   = var.buckets
  depends_on = [aws_s3_bucket.buckets]
  bucket     = each.value

  policy = lookup(local.bucket_policies, each.key,
    data.aws_iam_policy_document.https_only[each.key]
  ).json
}
