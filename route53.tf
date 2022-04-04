# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone
data "aws_route53_zone" "astrometrics" {
  provider = aws.route53
  name     = var.env == "dev" ? "dev.astrometrics.us" : "astrometrics.us"
}

locals {
  zone_id     = data.aws_route53_zone.astrometrics.zone_id
  app_domain  = data.aws_route53_zone.astrometrics.name
  api_domain  = "api.${local.app_domain}"
  sftp_domain = "sftp.${local.app_domain}"
}
