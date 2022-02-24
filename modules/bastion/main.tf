# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  disable_api_termination     = true
  iam_instance_profile        = var.instance_profile
  key_name                    = var.key_name

  tags = {
    Name = "Bastion Host"
  }

  root_block_device {
    volume_type = "gp2"
    volume_size = var.volume_size
    encrypted   = true

    tags = {
      Name = "Bastion Host"
    }
  }
}
