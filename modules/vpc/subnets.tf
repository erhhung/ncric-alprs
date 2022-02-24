locals {
  subnets = [{
    type = "public"
    cidr = var.subnet_cidrs.public
    }, {
    type = "private"
    cidr = var.subnet_cidrs.private
  }]
}

data "aws_region" "current" {}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "subnets" {
  for_each = { for subnet in local.subnets : subnet.type => subnet.cidr }

  vpc_id                                      = aws_vpc.main.id
  cidr_block                                  = each.value
  availability_zone                           = "${data.aws_region.current.name}a"
  map_public_ip_on_launch                     = each.key == "public"
  private_dns_hostname_type_on_launch         = "resource-name"
  enable_resource_name_dns_a_record_on_launch = true

  tags = {
    Name = "${var.vpc_name} ${each.key} subnet"
  }
}
