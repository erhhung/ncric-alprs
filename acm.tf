# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate
resource "aws_acm_certificate" "webapp" {
  provider                  = aws.us_east_1
  domain_name               = data.aws_route53_zone.astrometrics.name
  subject_alternative_names = ["api.${data.aws_route53_zone.astrometrics.name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  acm_dvos = {
    for dvo in aws_acm_certificate.webapp.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "acm_verification" {
  for_each = local.acm_dvos

  provider = aws.route53
  zone_id  = data.aws_route53_zone.astrometrics.zone_id
  name     = each.value.name
  type     = each.value.type
  ttl      = 3600
  records  = [each.value.record]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation
resource "aws_acm_certificate_validation" "webapp" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.webapp.arn
  validation_record_fqdns = [for rec in aws_route53_record.acm_verification : rec.fqdn]
}
