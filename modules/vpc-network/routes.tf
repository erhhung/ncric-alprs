# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "tables" {
  for_each = toset(local.subnet_names)

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name} ${each.value} routes"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route
resource "aws_route" "routes" {
  for_each = { for subnet in local.subnets : subnet.name => subnet }

  route_table_id         = aws_route_table.tables[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  gateway_id = (each.value.type == "private" ? null :
    aws_internet_gateway.main.id
  )
  nat_gateway_id = (each.value.type == "public" ? null :
    aws_nat_gateway.nats[each.key].id
  )
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "associations" {
  for_each = toset(local.subnet_names)

  subnet_id      = aws_subnet.subnets[each.value].id
  route_table_id = aws_route_table.tables[each.value].id
}
