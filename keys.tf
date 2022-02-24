# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair
resource "aws_key_pair" "admin" {
  key_name   = var.ssh_key.key_name
  public_key = var.ssh_key.public_key

  tags = {
    Purpose = "SSH admin access"
  }
}
