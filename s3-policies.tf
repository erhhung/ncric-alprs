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

data "aws_iam_policy_document" "sftp_bucket2" {
  for_each = toset(var.env == "none" ? [""] : [])

  source_policy_documents = [data.aws_iam_policy_document.https_only["sftp"].json]

  statement {
    sid       = "AllowSFTPLambdaPutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.buckets["sftp"].arn}/*"]

    principals {
      identifiers = [local.sftp_lambda_role_arn]
      type        = "AWS"
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
      identifiers = [
        "arn:${var.accounts[var.env].partition}:iam::${var.elb_account_id}:root"
      ]
      type = "AWS"
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

data "aws_iam_policy_document" "cf_origin" {
  source_policy_documents = [data.aws_iam_policy_document.https_only["webapp"].json]

  statement {
    sid       = "AllowCloudFrontAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.buckets["webapp"].arn}/*"]

    dynamic "principals" {
      for_each = toset(var.env == "dev" ? [""] : [])

      content {
        identifiers = aws_cloudfront_origin_access_identity.app[*].iam_arn
        type        = "AWS"
      }
    }
    dynamic "principals" {
      for_each = toset(var.env == "prod" ? [""] : [])

      content {
        identifiers = ["*"]
        type        = "*"
      }
    }

    # since webapp bucket in GovCloud must be made
    # public for CloudFront custom origin, restrict
    # access by using Referer header secret token:
    # https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html
    dynamic "condition" {
      for_each = toset(var.env == "prod" ? [""] : [])

      content {
        test     = "StringLike"
        variable = "aws:Referer"
        values   = [local.cf_referer]
      }
    }
  }
}

locals {
  bucket_policies = {
    sftp = (var.env == "none" ?
      data.aws_iam_policy_document.sftp_bucket2[""] :
      data.aws_iam_policy_document.https_only["sftp"]
    )
    audit  = data.aws_iam_policy_document.elb_logs
    webapp = data.aws_iam_policy_document.cf_origin
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy
resource "aws_s3_bucket_policy" "buckets" {
  depends_on = [aws_s3_bucket.buckets]
  for_each   = var.buckets
  bucket     = each.value

  policy = lookup(local.bucket_policies, each.key,
    data.aws_iam_policy_document.https_only[each.key]
  ).json
}
