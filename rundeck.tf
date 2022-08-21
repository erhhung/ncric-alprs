# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "rdproject_jar" {
  program = ["${path.module}/rundeck/mkjar.sh"]
}

locals {
  rundeck_user_data = [{
    path = "rundeck/astrometrics.rdproject.jar"
    file = "${path.module}/rundeck/astrometrics.rdproject.jar"
    type = "application/java-archive"
  }]
  rundeck_bootstrap = <<-EOT
${templatefile("${path.module}/rundeck/install.tftpl", {
  PG_HOST   = module.postgresql_server.private_domain
  WORKER_IP = module.worker_node.private_ip
  WORKER_OS = join("-", regex("/(ubuntu-.+)-arm64.+-(\\d+)", local.worker_ami))
  CLIENT_ID = var.AUTH0_SPA_CLIENT_ID
  # password and private key created in keys.tf
  atlas_pass   = local.atlas_pass
  rundeck_pass = local.rundeck_pass
  rundeck_key  = chomp(tls_private_key.rundeck_worker.private_key_pem)
  auth0_email  = var.auth0_user.email
  auth0_pass   = var.auth0_user.password
})}
${file("${path.module}/rundeck/install.sh")}
EOT
}

module "rundeck_user_data" {
  source = "./modules/userdata"

  depends_on = [
    data.external.rdproject_jar,
  ]
  bucket = data.aws_s3_bucket.user_data.id
  files  = local.rundeck_user_data
}

module "rundeck_config" {
  source = "./modules/config"

  service = "rundeck"
  path    = "${path.module}/rundeck/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    POSTGRESQL_HOST = module.postgresql_server.private_domain
  })
}
