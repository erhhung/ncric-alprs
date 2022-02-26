locals {
  tables = ["public", "private"]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
resource "aws_route_table" "tables" {
  for_each = toset(local.tables)

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name} ${each.value} routes"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route
resource "aws_route" "public" {
  route_table_id         = aws_route_table.tables["public"].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
resource "aws_route" "private" {
  route_table_id         = aws_route_table.tables["private"].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "associations" {
  for_each = toset(local.tables)

  subnet_id      = aws_subnet.subnets[each.value].id
  route_table_id = aws_route_table.tables[each.value].id
}
