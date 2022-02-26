output "instance_id" {
  value = aws_instance.host.id
}

output "data_volume_id" {
  value = length(aws_ebs_volume.data) > 0 ? one(aws_ebs_volume.data).id : null
}

output "public_ip" {
  value = var.assign_public_ip ? aws_instance.host.public_ip : null
}
