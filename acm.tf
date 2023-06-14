module "app_cert" {
  source = "./modules/cert"

  # https://developer.hashicorp.com/terraform/language/providers/configuration
  providers = {
    aws         = aws.cloudfront
    aws.route53 = aws.route53
  }
  domain  = local.app_domain
  zone_id = local.zone_id
}

module "api_cert" {
  source = "./modules/cert"

  providers = {
    aws.route53 = aws.route53
  }
  domain  = local.api_domain
  zone_id = local.zone_id
}

module "webhook_cert" {
  source = "./modules/cert"

  providers = {
    aws.route53 = aws.route53
  }
  domain  = local.webhook_domain
  zone_id = local.zone_id
}

output "cert_arns" {
  value = {
    app     = module.app_cert.arn
    api     = module.api_cert.arn
    webhook = module.webhook_cert.arn
  }
}
