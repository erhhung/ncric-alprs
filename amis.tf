locals {
  aws_amis = {
    amazon_linux2 = {
      owners = ["amazon"]
      filter = "amzn2-ami-hvm*-x86_64-*"
    }
    # not available in GovCloud yet!
    # amazon_al2022 = {
    #   owners = ["amazon"]
    #   filter = "al2022-ami-2022*"
    # }
    ubuntu_20arm = {
      owners = ["099720109477", "513442679011"] # Canonical
      filter = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "latest_amis" {
  for_each = local.aws_amis

  most_recent = true
  owners      = each.value.owners

  filter {
    name   = "name"
    values = [each.value.filter]
  }
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external
data "external" "current_amis" {
  # must convert nested object JSON to object
  # containing only string values per protocol
  program = [
    "bash", "-c", <<-EOT
    jq -cM 'with_entries(.value |= (.|tojson))' < <(
      terraform output -json current_amis 2> /dev/null || echo '{}'
    )
EOT
  ]
}

locals {
  current_amis = { # deserialize nested objects from external data source results
    for key, json in data.external.current_amis.result : key => jsondecode(json)
  }
  applied_amis = {
    for key, _ in local.aws_amis : key => coalesce(
      var.lock_ami_versions ? lookup(local.current_amis, key, null) : null,
      { id   = data.aws_ami.latest_amis[key].id,
        name = data.aws_ami.latest_amis[key].name,
      }
    )
  }
}
