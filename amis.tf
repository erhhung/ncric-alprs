# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*-x86_64-*"]
  }
}

# not available in GovCloud yet!
# data "aws_ami" "amazon_al2022" {
#   most_recent = true
#   owners      = ["amazon"]
# 
#   filter {
#     name   = "name"
#     values = ["al2022-ami-2022*"]
#   }
# }

data "aws_ami" "ubuntu_20arm" {
  most_recent = true
  owners      = ["099720109477", "513442679011"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-*"]
  }
}
