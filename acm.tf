module "app_cert" {
  source = "./modules/acm-certificate"

  # https://developer.hashicorp.com/terraform/language/providers/configuration
  providers = {
    aws         = aws.cloudfront
    aws.route53 = aws.route53
  }
  domain  = local.app_domain
  zone_id = local.zone_id
}

module "api_cert" {
  source = "./modules/acm-certificate"

  providers = {
    aws.route53 = aws.route53
  }
  domain  = local.api_domain
  zone_id = local.zone_id
}

module "webhook_cert" {
  source = "./modules/acm-certificate"

  providers = {
    aws.route53 = aws.route53
  }
  domain  = local.webhook_domain
  zone_id = local.zone_id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "webhook_cert_arn" {
  name           = "/webhook/cert/arn"
  type           = "String"
  insecure_value = module.webhook_cert.arn
}

output "cert_arns" {
  value = {
    app     = module.app_cert.arn
    api     = module.api_cert.arn
    webhook = module.webhook_cert.arn
  }
}
