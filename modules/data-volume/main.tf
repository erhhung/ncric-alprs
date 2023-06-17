# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume
resource "aws_ebs_volume" "data" {
  type              = var.data_volume_type
  size              = var.data_volume_size
  availability_zone = var.availability_zone
  encrypted         = true

  tags = {
    Name = var.data_volume_name
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment
resource "aws_volume_attachment" "data" {
  volume_id   = aws_ebs_volume.data.id
  instance_id = var.instance_id
  device_name = var.device_name
}
