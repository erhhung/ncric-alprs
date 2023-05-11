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
  depends_on = [aws_s3_bucket.buckets]
  for_each   = var.buckets
  bucket     = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

locals {
  private_buckets = {
    # allow webapp bucket in GovCloud to be public so CloudFront can
    # access the custom origin using secret token in Referer header:
    # https://aws.amazon.com/premiumsupport/knowledge-center/cloudfront-serve-static-website/
    for key, name in var.buckets : key => name if var.env != "prod" || key != "webapp"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
resource "aws_s3_bucket_public_access_block" "buckets" {
  depends_on = [aws_s3_bucket.buckets]
  for_each   = local.private_buckets
  bucket     = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls
resource "aws_s3_bucket_ownership_controls" "buckets" {
  depends_on = [aws_s3_bucket.buckets]
  for_each   = var.buckets
  bucket     = each.value

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_acl
resource "aws_s3_bucket_acl" "buckets" {
  depends_on = [aws_s3_bucket.buckets]
  for_each   = local.private_buckets
  bucket     = each.value

  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/acl-overview.html#canned-acl
  acl = each.key == "audit" ? "log-delivery-write" : "private"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration
resource "aws_s3_bucket_lifecycle_configuration" "sftp" {
  bucket = aws_s3_bucket.buckets["sftp"].id

  rule {
    id     = "glacier-30-expire-180"
    status = "Disabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    expiration {
      days = 180
    }
  }
  rule {
    id     = "expire-7"
    status = "Enabled"

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.buckets["media"].id

  rule {
    id     = "infrequent-30"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.buckets["backup"].id

  rule {
    # can go to STANDARD_IA only after 30 days
    id     = "infrequent-30"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
  rule {
    id     = "postgresql-expire-7"
    status = "Disabled"

    filter {
      prefix = "postgresql/"
    }
    expiration {
      days = 7
    }
  }
  rule {
    # apply the same rule as SFTP bucket
    # can go to Glacier only after 30 days
    id     = "flock-glacier-30-expire-180"
    status = "Disabled"

    filter {
      prefix = "flock/"
    }
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    expiration {
      days = 180
    }
  }
  rule {
    id     = "flock-expire-1"
    status = "Enabled"

    filter {
      prefix = "flock/"
    }
    expiration {
      days = 1
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "audit" {
  bucket = aws_s3_bucket.buckets["audit"].id

  rule {
    id     = "expire-30"
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
