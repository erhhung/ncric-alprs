locals {
  shared_user_data = [{
    path = "shared/.bash_aliases"
    data = file("${path.module}/shared/.bash_aliases")
    }, {
    path = "shared/.gitconfig"
    data = file("${path.module}/shared/.gitconfig")
    }, {
    path = "shared/.screenrc"
    data = file("${path.module}/shared/.screenrc")
    }, {
    path = "shared/.emacs"
    data = file("${path.module}/shared/.emacs")
  }]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "shared_user_data" {
  for_each = { for object in local.shared_user_data : basename(object.path) => object }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = "text/plain"
  content      = chomp(each.value.data)
  source_hash  = md5(each.value.data)
}

locals {
  # sed -En 's/^.+\$\{([a-zA-Z0-9_]+)\}.*$/\1/p' *.yaml | sort | uniq
  config_values = {
    AWS_REGION              = local.region
    APP_DOMAIN              = local.app_domain
    ALPRS_PASSWORD          = local.alprs_pass
    ATLAS_PASSWORD          = local.atlas_pass
    AUDIT_BUCKET            = var.buckets["audit"]
    AUDIT_ACCESS_KEY        = aws_iam_access_key.users["alprs-audit"].id
    AUDIT_SECRET_KEY        = aws_iam_access_key.users["alprs-audit"].secret
    AUTH0_M2M_CLIENT_ID     = var.AUTH0_M2M_CLIENT_ID
    AUTH0_M2M_CLIENT_SECRET = var.AUTH0_M2M_CLIENT_SECRET
    AUTH0_SPA_CLIENT_ID     = var.AUTH0_SPA_CLIENT_ID
    AUTH0_SPA_CLIENT_SECRET = var.AUTH0_SPA_CLIENT_SECRET
    CONDUCTOR_HOST          = module.conductor_server.private_domain
    ELASTICSEARCH_HOST      = module.elasticsearch_server.private_domain
    MAPBOX_PUBLIC_TOKEN     = var.MAPBOX_PUBLIC_TOKEN
    MEDIA_BUCKET            = var.buckets["media"]
    MEDIA_ACCESS_KEY        = aws_iam_access_key.users["alprs-media"].id
    MEDIA_SECRET_KEY        = aws_iam_access_key.users["alprs-media"].secret
    POSTGRESQL_HOST         = module.postgresql_server.private_domain
    SES_ACCESS_KEY          = aws_iam_access_key.users["alprs-mail"].id
    SMTP_PASSWORD           = aws_iam_access_key.users["alprs-mail"].ses_smtp_password_v4
  }
}
