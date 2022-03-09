output "env" {
  value = var.env
}

output "iam_user_access_keys" {
  value = { for user in local.users : user.name => {
    access_key_id     = aws_iam_access_key.users[user.name].id,
    secret_access_key = aws_iam_access_key.users[user.name].secret,
  } }
  sensitive = true
}

output "app_cf_domain" {
  value = aws_cloudfront_distribution.app.domain_name
}

output "api_elb_domain" {
  value = aws_lb.api.dns_name
}
