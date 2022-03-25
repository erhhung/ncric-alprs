# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "host" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_groups
  associate_public_ip_address = var.assign_public_ip
  iam_instance_profile        = var.instance_profile
  key_name                    = var.key_name
  user_data                   = var.user_data

  # NOTE: any change that causes the instance to be recreated will cause
  # a termination failure unless API termination is MANUALLY re-enabled:
  # aws ec2 modify-instance-attribute --instance-id i-XXX --no-disable-api-termination
  disable_api_termination = false

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
