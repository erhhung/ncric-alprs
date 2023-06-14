# IMPORTANT: CloudFront is NOT available in GovCloud: it must be configured in us-east-1
# region in the commercial account using a custom origin to URL of S3 bucket in GovCloud
# https://docs.aws.amazon.com/govcloud-us/latest/UserGuide/setting-up-cloudfront.html

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_identity
resource "aws_cloudfront_origin_access_identity" "app" {
  count    = var.env == "dev" ? 1 : 0
  comment  = "Identity allowed access to app S3 bucket"
  provider = aws.cloudfront
}

locals {
  s3_origin_id   = "app_s3_origin"
  cached_methods = ["GET", "HEAD"]
  cf_logs_bucket = replace(var.buckets["audit"], var.env, "dev")
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution
resource "aws_cloudfront_distribution" "app" {
  depends_on = [module.app_cert]
  provider   = aws.cloudfront

  enabled             = true
  comment             = "AstroMetrics ${var.env} frontend"
  aliases             = [local.app_domain]
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US+EU

  origin {
    domain_name = aws_s3_bucket.buckets["webapp"].bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    dynamic "s3_origin_config" {
      for_each = toset(var.env == "dev" ? [""] : [])

      content {
        origin_access_identity = one(aws_cloudfront_origin_access_identity.app[*].cloudfront_access_identity_path)
      }
    }
    dynamic "custom_origin_config" {
      for_each = toset(var.env == "prod" ? [""] : [])

      content {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }

    # since webapp bucket in GovCloud must be made
    # public for CloudFront custom origin, restrict
    # access by using Referer header secret token:
    # https://aws.amazon.com/premiumsupport/knowledge-center/cloudfront-serve-static-website/
    dynamic "custom_header" {
      for_each = toset(var.env == "prod" ? [""] : [])

      content {
        name  = "Referer"
        value = local.cf_referer
      }
    }
  }

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    target_origin_id       = local.s3_origin_id
    allowed_methods        = local.cached_methods
    cached_methods         = local.cached_methods
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn      = module.app_cert.arn
    minimum_protocol_version = "TLSv1.2_2018"
    ssl_support_method       = "sni-only"
  }

  logging_config {
    # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/AccessLogs.html
    bucket          = "${local.cf_logs_bucket}.s3.amazonaws.com"
    prefix          = "AWSLogs/${local.account}/cloudfront"
    include_cookies = false
  }

  restrictions {
    geo_restriction {
      # https://www.iso.org/obp/ui/#search/code/
      restriction_type = var.geo_restriction ? "whitelist" : "none"
      locations        = var.geo_restriction ? ["US"] : []
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "app" {
  provider = aws.route53
  zone_id  = local.zone_id
  name     = local.app_domain
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = true
  }

  dynamic "geolocation_routing_policy" {
    for_each = toset(var.geo_restriction ? [""] : [])

    content {
      country = "US"
    }
  }
  set_identifier = var.geo_restriction ? "US" : null
}

output "app_cf_domain" {
  value = aws_cloudfront_distribution.app.domain_name
}
