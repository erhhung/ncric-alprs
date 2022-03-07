# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone
data "aws_route53_zone" "astrometrics" {
  provider = aws.route53
  name     = var.env == "dev" ? "dev.astrometrics.us" : "astrometrics.us"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_identity
resource "aws_ses_domain_identity" "astrometrics" {
  domain = data.aws_route53_zone.astrometrics.name
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "ses_verification" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.astrometrics.zone_id
  name     = "_amazonses.${aws_ses_domain_identity.astrometrics.id}"
  type     = "TXT"
  ttl      = 3600
  records  = [aws_ses_domain_identity.astrometrics.verification_token]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_mail_from
resource "aws_ses_domain_mail_from" "astrometrics" {
  domain           = aws_ses_domain_identity.astrometrics.domain
  mail_from_domain = "bounce.${aws_ses_domain_identity.astrometrics.domain}"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.astrometrics.zone_id
  name     = aws_ses_domain_mail_from.astrometrics.mail_from_domain
  type     = "MX"
  ttl      = 3600
  records  = ["10 feedback-smtp.${data.aws_region.current.name}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_txt" {
  provider = aws.route53
  zone_id  = data.aws_route53_zone.astrometrics.zone_id
  name     = aws_ses_domain_mail_from.astrometrics.mail_from_domain
  type     = "TXT"
  ttl      = 3600
  records  = ["v=spf1 include:amazonses.com -all"]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ses_domain_dkim
resource "aws_ses_domain_dkim" "astrometrics" {
  domain = aws_ses_domain_identity.astrometrics.domain
}

resource "aws_route53_record" "ses_domain_dkim" {
  for_each = toset(aws_ses_domain_dkim.astrometrics.dkim_tokens)

  provider = aws.route53
  zone_id  = data.aws_route53_zone.astrometrics.zone_id
  name     = "${each.value}._domainkey"
  type     = "CNAME"
  ttl      = 3600
  records  = ["${each.value}.dkim.amazonses.com"]
}
