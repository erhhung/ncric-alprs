# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_identity
resource "aws_cloudfront_origin_access_identity" "webapp" {
  comment = "Identity allowed access to webapp S3 bucket"
}

locals {
  s3_origin_id   = "webapp_s3_origin"
  cached_methods = ["GET", "HEAD"]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution
resource "aws_cloudfront_distribution" "webapp" {
  enabled             = true
  comment             = "Astrometrics webapp frontend"
  aliases             = [data.aws_route53_zone.astrometrics.name]
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US+EU

  origin {
    domain_name = aws_s3_bucket.buckets["webapp"].bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.webapp.cloudfront_access_identity_path
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
    acm_certificate_arn      = aws_acm_certificate.webapp.arn
    minimum_protocol_version = "TLSv1.2_2018"
    ssl_support_method       = "sni-only"
  }
  logging_config {
    bucket          = "${local.audit_bucket}.s3.amazonaws.com"
    prefix          = "logs/cloudfront/"
    include_cookies = false
  }
  restrictions {
    geo_restriction {
      # https://www.iso.org/obp/ui/#search/code/
      restriction_type = "whitelist"
      locations        = ["US"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "webapp" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.astrometrics.zone_id
  name     = data.aws_route53_zone.astrometrics.name
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.webapp.domain_name
    zone_id                = aws_cloudfront_distribution.webapp.hosted_zone_id
    evaluate_target_health = true
  }
}
