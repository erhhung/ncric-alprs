module "services_sg" {
  source = "./modules/secgroup"

  name        = "services-sg"
  description = "Allow Hazelcast/Jetty traffic"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
    ingress_570x = {
      from_port   = 5701
      to_port     = 5703
      cidr_blocks = local.subnet_cidrs["private"]
    }
    ingress_8080 = {
      from_port   = 8080
      cidr_blocks = local.subnet_cidrs["private"]
    }
    # traffic from ELB
    ingress_8443 = {
      from_port   = 8443
      cidr_blocks = local.all_subnet_cidrs
    }
  }
}

locals {
  shared_user_data = [{
    path = "shared/authorized_keys"
    data = local.authorized_keys
    }, {
    path = "shared/.bash_aliases"
    data = <<-EOF
${file("${path.module}/shared/.bash_aliases")}
${file("${path.module}/shared/.bash_aliases_ubuntu")}
EOF
    }, {
    path = "shared/lesspipe.sh"
    file = "${path.module}/shared/lesspipe.sh"
    }, {
    path = "shared/.lessfilter"
    file = "${path.module}/shared/.lessfilter"
    }, {
    path = "shared/.gitconfig"
    file = "${path.module}/shared/.gitconfig"
    }, {
    path = "shared/.screenrc"
    file = "${path.module}/shared/.screenrc"
    }, {
    path = "shared/.emacs"
    file = "${path.module}/shared/.emacs"
  }]
}

module "shared_user_data" {
  source = "./modules/userdata"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.shared_user_data
}

locals {
  # list placeholder variables in YAML/properties templates:
  # (shopt -s nullglob; sed -En 's/^.+\$\{([a-zA-Z0-9_]+)\}.*$/\1/p' *.{yaml,properties} | sort | uniq)
  #
  # NOTE: the reason why there are no _HOST config values here even though
  # nearly all config files require POSTGRESQL_HOST and ELASTICSEARCH_HOST
  # is because "enable.sh" and "disable.sh" can remove those corresponding
  # .tf files from the deployment scope while keeping other hosts, causing
  # dependency errors
  config_values = {
    AWS_REGION              = local.region
    APP_DOMAIN              = local.app_domain
    ATLAS_PASSWORD          = local.atlas_pass
    ALPRS_PASSWORD          = local.alprs_pass
    RUNDECK_PASSWORD        = local.rundeck_pass
    AUTH0_SPA_CLIENT_ID     = var.AUTH0_SPA_CLIENT_ID
    AUTH0_SPA_CLIENT_SECRET = var.AUTH0_SPA_CLIENT_SECRET
    AUTH0_M2M_CLIENT_ID     = var.AUTH0_M2M_CLIENT_ID
    AUTH0_M2M_CLIENT_SECRET = var.AUTH0_M2M_CLIENT_SECRET
    MAPBOX_PUBLIC_TOKEN     = var.MAPBOX_PUBLIC_TOKEN
    AUDIT_BUCKET            = var.buckets["audit"]
    MEDIA_BUCKET            = var.buckets["media"]
    AUDIT_ACCESS_KEY        = aws_iam_access_key.users["alprs-audit"].id
    AUDIT_SECRET_KEY        = aws_iam_access_key.users["alprs-audit"].secret
    MEDIA_ACCESS_KEY        = aws_iam_access_key.users["alprs-media"].id
    MEDIA_SECRET_KEY        = aws_iam_access_key.users["alprs-media"].secret
    SES_ACCESS_KEY          = aws_iam_access_key.users["alprs-mail"].id
    SMTP_PASSWORD           = aws_iam_access_key.users["alprs-mail"].ses_smtp_password_v4
  }
}
