# https://developer.hashicorp.com/terraform/language/providers/configuration
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 4.2"
      configuration_aliases = [aws.route53]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = var.domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  dvos = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "acm_validations" {
  for_each = local.dvos

  provider        = aws.route53
  zone_id         = var.zone_id
  name            = each.value.name
  type            = "CNAME"
  ttl             = 3600
  records         = [each.value.record]
  allow_overwrite = true
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for rec in aws_route53_record.acm_validations : rec.fqdn]
}
