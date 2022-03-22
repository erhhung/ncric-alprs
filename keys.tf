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
