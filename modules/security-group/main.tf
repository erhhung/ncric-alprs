locals {
  rules = merge(var.rules, {
    egress_all = {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      cidr_blocks = ["0.0.0.0/0"]
    }
  })
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "group" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id

  tags = {
    Name = var.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule
resource "aws_security_group_rule" "rules" {
  for_each = local.rules

  security_group_id = aws_security_group.group.id
  type              = regex("^[a-z]+", each.key)
  from_port         = each.value.from_port
  to_port           = coalesce(each.value.to_port, each.value.from_port)
  protocol          = coalesce(each.value.protocol, "tcp")
  cidr_blocks       = each.value.cidr_blocks
}
