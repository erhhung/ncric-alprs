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

data "external" "old_pg_pass" {
  program = [
    "bash", "-c",
    "terraform output -json postgresql_user_logins 2> /dev/null || echo '{}'",
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
