# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "conductor_cwagent_json" {
  program = [
    "${path.module}/monitoring/cwagent.sh",
    "shared", "HOST=conductor"
  ]
}

locals {
  conductor_scripts_path = "${path.module}/conductor/scripts"
  conductor_user_data = flatten([[
    for path in fileset(local.conductor_scripts_path, "**") : {
      path = "conductor/scripts/${path}"
      file = "${local.conductor_scripts_path}/${path}"
    }], {
    path = "conductor/cwagent.json"
    data = data.external.conductor_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "conductor/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/conductor/boot.tftpl", {
    ENV           = var.env
    S3_URL        = local.user_data_s3_url
    GH_TOKEN      = var.GITHUB_ACCESS_TOKEN
    FROM_EMAIL    = local.alprs_sender_email
    BACKUP_BUCKET = var.buckets["backup"]
    CONFIG_BUCKET = var.buckets["config"]
  })}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOF
}])
}

module "conductor_user_data" {
  source = "./modules/userdata"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.conductor_user_data
}

locals {
  conductor_bootstrap = <<-EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "conductor"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "conductor_server" {
  source = "./modules/instance"

  depends_on = [
    module.shared_user_data,
    module.conductor_user_data,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["conductor"]
  instance_name    = local.hosts["conductor"]
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  private_ip       = local.private_ips["conductor"]
  security_groups  = [module.services_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.conductor_bootstrap)
}

module "conductor_config" {
  source = "./modules/config"

  depends_on = [
    data.external.rhizome_jks,
  ]
  service = "conductor"
  path    = "${path.module}/conductor/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    CONDUCTOR_HOST     = module.conductor_server.private_domain
    POSTGRESQL_HOST    = module.postgresql_server.private_domain
    ELASTICSEARCH_HOST = module.elasticsearch_server.private_domain
  })
}

output "conductor_instance_id" {
  value = module.conductor_server.instance_id
}
output "conductor_instance_ami" {
  value = module.conductor_server.instance_ami
}
output "conductor_private_domain" {
  value = module.conductor_server.private_domain
}
output "conductor_private_ip" {
  value = module.conductor_server.private_ip
}
