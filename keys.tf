# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair
resource "aws_key_pair" "admin" {
  key_name   = var.ssh_keys[0].key_name
  public_key = var.ssh_keys[0].public_key

  tags = {
    Purpose = "SSH admin access"
  }
}

locals {
  # additional SSH keys stored in S3 as userdata/shared/authorized_keys (see shared.tf)
  authorized_keys = join("\n", [for i, key in var.ssh_keys : key.public_key if i > 0])
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "rhizome_jks" {
  program = [
    "${path.module}/shared/upcert.sh",
    local.app_domain,
  ]
}

#################### PostgreSQL ####################

data "external" "old_pg_pass" {
  program = [
    "bash", "-c",
    "terraform output -json postgresql_user_logins 2> /dev/null || echo -n '{}'",
  ]
}
data "external" "new_pg_pass" {
  program = [
    "${path.module}/shared/pwgen.sh",
    "alprs_user", "atlas_user",
  ]
}

locals {
  old_pg_pass = data.external.old_pg_pass.result
  new_pg_pass = data.external.new_pg_pass.result

  alprs_pass = coalesce(
    lookup(local.old_pg_pass, "alprs_user", null),
    local.new_pg_pass["alprs_user"]
  )
  atlas_pass = coalesce(
    lookup(local.old_pg_pass, "atlas_user", null),
    local.new_pg_pass["atlas_user"]
  )
}

locals {
  # CloudFront custom origin Referer header secret
  # token used only in prod environment where the
  # webapp bucket in GovCloud must be made public
  cf_referer = sha1("${local.alprs_pass}_${local.atlas_pass}")
}

#################### Rundeck ####################

data "external" "old_rd_pass" {
  program = [
    "bash", "-c", <<-EOT
      secret=$(terraform output -json rundeck_admin_pass 2> /dev/null)
      # secret will be quoted string or empty
      echo -n '{"secret":'$${secret:-null}'}'
EOT
  ]
}
data "external" "new_rd_pass" {
  program = ["${path.module}/shared/pwgen.sh"]
}

locals {
  old_rd_pass = data.external.old_rd_pass.result
  new_rd_pass = data.external.new_rd_pass.result

  rundeck_pass = coalesce(
    local.old_rd_pass["secret"],
    local.new_rd_pass["secret"],
  )
}

# https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key
resource "tls_private_key" "rundeck_worker" {
  algorithm = "RSA"
  rsa_bits  = 2048
}
