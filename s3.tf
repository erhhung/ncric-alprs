# local.xxx_bucket variables are defined in variables.tf
# to accept overrides from var.xxx_bucket with var.env a
# part of the default bucket names.
locals {
  buckets = [{
    type = "webapp"
    name = local.webapp_bucket
    }, {
    type = "config"
    name = local.config_bucket
    }, {
    type = "audit"
    name = local.audit_bucket
    }, {
    type = "media"
    name = local.media_bucket
    }, {
    type = "sftp"
    name = local.sftp_bucket
  }]
  user_data_bucket = data.external.backend_config.result.bucket
  user_data_s3_url = "s3://${local.user_data_bucket}"
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "backend_config" {
  program = [
    "${path.module}/shared/tfvars.sh",
    "${path.module}/config/${var.env}.conf",
  ]
}

# also use the Terraform state bucket to store instance
# initialization scripts that are too big for user data
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/s3_bucket
data "aws_s3_bucket" "user_data" {
  bucket = local.user_data_bucket
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket
resource "aws_s3_bucket" "buckets" {
  for_each = { for bucket in local.buckets : bucket.type => bucket.name }
  bucket   = each.value # created in same region as provider
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = { for bucket in local.buckets : bucket.type => bucket.name }
  bucket   = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = { for bucket in local.buckets : bucket.type => bucket.name }
  bucket   = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_website_configuration
resource "aws_s3_bucket_website_configuration" "webapp" {
  bucket = aws_s3_bucket.buckets["webapp"].id

  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "error.html"
  }
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
