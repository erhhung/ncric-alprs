# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone
data "aws_route53_zone" "astrometrics" {
  provider = aws.route53
  name     = var.domain
}

locals {
  zone_id        = data.aws_route53_zone.astrometrics.zone_id
  app_domain     = var.domain
  api_domain     = "api.${var.domain}"
  sftp_domain    = "sftp.${var.domain}"
  webhook_domain = "webhook.${var.domain}"
  app_url        = "https://${local.app_domain}"
  api_url        = "https://${local.api_domain}"
}
