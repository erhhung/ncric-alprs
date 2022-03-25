module "elb_http_sg" {
  source = "./modules/secgrp"

  name        = "elb-http-sg"
  description = "Allow HTTP/S inbound traffic"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
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
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb
resource "aws_lb" "api" {
  depends_on = [module.elb_http_sg]

  name                       = "api-lb"
  load_balancer_type         = "application"
  subnets                    = local.public_subnet_ids
  security_groups            = [module.elb_http_sg.id]
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
  protocol_version = "HTTP1" # Postman will not work with HTTP2
  target_type      = "instance"
  vpc_id           = module.main_vpc.vpc_id

  health_check {
    path     = "/admin/ping"
    protocol = "HTTPS"
    matcher  = "200"
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
