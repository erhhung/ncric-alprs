output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_ids" {
  value = { for name in local.subnet_names :
    name => aws_subnet.subnets[name].id
  }
}
