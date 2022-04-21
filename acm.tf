# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
resource "aws_acm_certificate" "app" {
  provider          = aws.cloudfront
  domain_name       = local.app_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_acm_certificate" "api" {
  domain_name       = local.api_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  certs = [
    aws_acm_certificate.app,
    aws_acm_certificate.api,
  ]
  acm_dvos = merge([
    for cert in local.certs : {
      for dvo in cert.domain_validation_options : dvo.domain_name => {
        name   = dvo.resource_record_name
        type   = dvo.resource_record_type
        record = dvo.resource_record_value
      }
    }
  ]...)
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "cert_validations" {
  for_each = local.acm_dvos

  provider = aws.route53
  zone_id  = local.zone_id
  name     = each.value.name
  type     = each.value.type
  ttl      = 3600
  records  = [each.value.record]
}

locals {
  app_fqdns = [for dom, rec in aws_route53_record.cert_validations :
    rec.fqdn if length(regexall("\\.api\\.", dom)) == 0
  ]
  api_fqdns = [for dom, rec in aws_route53_record.cert_validations :
    rec.fqdn if length(regexall("\\.api\\.", dom)) > 0
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_acm_certificate_validation" "app" {
  provider                = aws.cloudfront
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = local.app_fqdns
}
resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = local.api_fqdns
}
