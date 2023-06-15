locals {
  subnets = flatten([for type, cidrs in var.subnet_cidrs : [
    for i, cidr in cidrs : {
      name = "${type}${i + 1}"
      type = type
      cidr = cidr
      zone = "${local.region}${element(local.zones, i)}"
      # https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
      k8s_tag = "kubernetes.io/role/${type == "public" ? "elb" : "internal-elb"}"
    }]
  ])
  subnet_names    = [for subnet in local.subnets : subnet.name]
  public_subnets  = [for i, _ in var.subnet_cidrs.public  :  "public${i + 1}"]
  private_subnets = [for i, _ in var.subnet_cidrs.private : "private${i + 1}"]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "subnets" {
  for_each   = { for subnet in local.subnets : subnet.name => subnet }
  depends_on = [aws_internet_gateway.main]

  vpc_id                                      = aws_vpc.main.id
  cidr_block                                  = each.value.cidr
  availability_zone                           = each.value.zone
  map_public_ip_on_launch                     = each.value.type == "public"
  private_dns_hostname_type_on_launch         = "resource-name"
  enable_resource_name_dns_a_record_on_launch = true

  tags = {
    Name = "${var.vpc_name} ${each.key} subnet"
    # https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
    "${each.value.k8s_tag}" = "1"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "nats" {
  for_each   = toset(local.private_subnets)
  depends_on = [aws_internet_gateway.main]
  domain     = "vpc"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
resource "aws_nat_gateway" "nats" {
  for_each = { for i, name in local.private_subnets :
    name => element(local.public_subnets, i)
  }

  allocation_id = aws_eip.nats[each.key].id
  subnet_id     = aws_subnet.subnets[each.value].id

  tags = {
    Name = "${var.vpc_name} ${each.key} NAT"
  }
}
