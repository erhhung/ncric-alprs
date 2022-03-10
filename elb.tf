# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "allow_http" {
  name        = "allow-http-sg"
  description = "Allow HTTP/S inbound traffic"
  vpc_id      = module.main_vpc.vpc_id
}

locals {
  sg_rules = {
    ingress_443 = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_80 = {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all = {
      from_port   = 0
      to_port     = 0
      protocol    = -1
      cidr_blocks = flatten(values(local.subnet_cidrs))
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule
resource "aws_security_group_rule" "allow_http" {
  for_each = local.sg_rules

  security_group_id = aws_security_group.allow_http.id
  type              = regex("^[a-z]+", each.key)
  cidr_blocks       = each.value.cidr_blocks
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  protocol          = each.value.protocol
}

locals {
  public_subnet_ids = [for name, id in module.main_vpc.subnet_ids :
    id if length(regexall("public", name)) > 0
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "api" {
  name                       = "api-lb"
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.allow_http.id]
  subnets                    = local.public_subnet_ids
  drop_invalid_header_fields = true

  access_logs {
    # https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/enable-access-logs.html
    bucket  = var.buckets["audit"]
    enabled = true
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group
resource "aws_lb_target_group" "api" {
  name             = "api-tg"
  port             = 8443
  protocol         = "HTTPS"
  protocol_version = "HTTP2"
  target_type      = "instance"
  vpc_id           = module.main_vpc.vpc_id

  health_check {
    path     = "/"
    interval = 20
  }
}

# see datastore.tf for the aws_lb_target_group_attachment.api resource.

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener
resource "aws_lb_listener" "api_https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.api.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_listener" "api_http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "api" {
  provider = aws.route53
  zone_id  = local.zone_id
  name     = local.api_domain
  type     = "A"

  alias {
    name                   = aws_lb.api.dns_name
    zone_id                = aws_lb.api.zone_id
    evaluate_target_health = true
  }
}
