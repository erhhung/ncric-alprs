# reference implementation: https://github.com/PatientPing/terraform-aws-transfer-sftp

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_server
resource "aws_transfer_server" "sftp" {
  security_policy_name = "TransferSecurityPolicy-FIPS-2020-06"
  logging_role         = aws_iam_role.sftp_logger.arn
  force_destroy        = true

  pre_authentication_login_banner = <<-EOT
********************************
** MaiVERIC ALPRS SFTP Server **
********************************
EOT
  # https://docs.aws.amazon.com/transfer/latest/userguide/requirements-dns.html
  # https://github.com/hashicorp/terraform-provider-aws/issues/20612
}

# https://github.com/hashicorp/terraform-provider-aws/issues/18077
# https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource
resource "null_resource" "aws_transfer_server_custom_hostname" {
  triggers = {
    hosted_zone = local.zone_id
    hostname    = local.sftp_domain
  }
  depends_on = [aws_transfer_server.sftp]

  provisioner "local-exec" {
    command = <<-EOF
aws transfer tag-resource \
  --profile ${var.aws_provider.profile} \
  --region  ${var.aws_provider.region}  \
  --arn     ${aws_transfer_server.sftp.arn} \
  --tags \
    Key=aws:transfer:route53HostedZoneId,Value=/hostedzone/${local.zone_id} \
    Key=aws:transfer:customHostname,Value=${local.sftp_domain}
EOF
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_user
resource "aws_transfer_user" "sftp_users" {
  for_each = var.sftp_users

  server_id      = aws_transfer_server.sftp.id
  user_name      = each.key
  role           = aws_iam_role.sftp_transfer.arn
  home_directory = "/${var.buckets["sftp"]}/${each.key}"
  policy         = data.aws_iam_policy_document.sftp_user.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_ssh_key
# ed25519 ssh keys are NOT supported: https://repost.aws/questions/QUSr4tgKMQS16Yp42ojLis5w
resource "aws_transfer_ssh_key" "sftp_users" {
  for_each   = var.sftp_users
  depends_on = [aws_transfer_user.sftp_users]

  server_id = aws_transfer_server.sftp.id
  user_name = each.key
  body      = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "sftp" {
  provider = aws.route53
  zone_id  = local.zone_id
  name     = local.sftp_domain
  type     = "CNAME"
  records  = ["${aws_transfer_server.sftp.endpoint}."]
  ttl      = 300
}
