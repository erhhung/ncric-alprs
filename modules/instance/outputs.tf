output "ami_id" {
  value = aws_instance.host.ami
}

output "ami_name" {
  value = data.aws_ami.host.name
}

output "instance_id" {
  value = aws_instance.host.id
}

output "instance_az" {
  value = aws_instance.host.availability_zone
}

output "public_domain" {
  value = var.assign_public_ip ? aws_instance.host.public_dns : null
}

output "public_ip" {
  value = var.assign_public_ip ? aws_instance.host.public_ip : null
}

output "private_domain" {
  value = aws_instance.host.private_dns
}

output "private_ip" {
  value = aws_instance.host.private_ip
}
