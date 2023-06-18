# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "webhook_auth0_id" {
  name           = "/auth0/webhook/id"
  type           = "String"
  insecure_value = var.AUTH0_WEBHOOK_CLIENT_ID
}

resource "aws_ssm_parameter" "webhook_auth0_secret" {
  name  = "/auth0/webhook/secret"
  type  = "SecureString"
  value = var.AUTH0_WEBHOOK_CLIENT_SECRET
}
