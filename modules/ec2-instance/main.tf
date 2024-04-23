# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "host" {
  owners = [
    "self",
    "amazon",
    "microsoft",
    "aws-marketplace",
    "099720109477", # Canonical
    "513442679011", # Canonical
  ]
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "host" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  associate_public_ip_address = var.assign_public_ip
  vpc_security_group_ids      = var.security_groups
  iam_instance_profile        = var.instance_profile
  key_name                    = var.key_name
  user_data                   = var.user_data

  # NOTE: any change that causes the instance to be recreated will cause
  # a termination failure unless API termination is MANUALLY re-enabled:
  # aws ec2 modify-instance-attribute --instance-id i-XXX --no-disable-api-termination
  disable_api_termination = false

  dynamic "instance_market_options" {
    # launch as spot instance if max_spot_price is > 0
    for_each = toset(var.max_spot_price > 0 ? [""] : [])

    content {
      market_type = "spot"

      # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#spot-options
      spot_options {
        spot_instance_type             = "persistent"
        instance_interruption_behavior = "stop" # Graviton does not support hibernation
        max_price                      = var.max_spot_price
      }
    }
  }

  tags = {
    Name = var.instance_name
  }

  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = true

    tags = {
      Name = var.instance_name
    }
  }
}
