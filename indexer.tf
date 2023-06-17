# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "indexer_cwagent_json" {
  program = [
    "${path.module}/monitoring/cwagent.sh",
    "shared", "HOST=indexer"
  ]
}

locals {
  indexer_scripts_path = "${path.module}/indexer/scripts"
  indexer_user_data = flatten([[
    for path in fileset(local.indexer_scripts_path, "**") : {
      path = "indexer/scripts/${path}"
      file = "${local.indexer_scripts_path}/${path}"
    }], {
    path = "indexer/cwagent.json"
    data = data.external.indexer_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "indexer/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/indexer/boot.tftpl", {
    ENV           = var.env
    S3_URL        = local.user_data_s3_url
    GITHUB_TOKEN  = var.GITHUB_ACCESS_TOKEN
    BACKUP_BUCKET = var.buckets["backup"]
    CONFIG_BUCKET = var.buckets["config"]
    DATASTORE_IP  = module.datastore_server.private_ip
    CLIENT_ID     = var.AUTH0_SPA_CLIENT_ID
    # passwords are created in keys.tf
    auth0_email = var.auth0_user.email
    auth0_pass  = var.auth0_user.password
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOF
  }])
}

module "indexer_user_data" {
  source = "./modules/user-data"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.indexer_user_data
}

locals {
  indexer_bootstrap = <<-EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "indexer"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "indexer_server" {
  source = "./modules/ec2-instance"

  depends_on = [
    module.shared_user_data,
    module.indexer_user_data,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["indexer"]
  instance_name    = local.hosts["indexer"]
  root_volume_size = var.root_volume_sizes["indexer"]
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  private_ip       = local.private_ips["indexer"]
  security_groups  = [module.services_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.indexer_bootstrap)
}

module "indexer_config" {
  source = "./modules/service-config"

  depends_on = [
    data.external.rhizome_jks,
  ]
  service = "indexer"
  path    = "${path.module}/indexer/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    CONDUCTOR_HOST     = module.conductor_server.private_domain
    POSTGRESQL1_HOST   = module.postgresql_server[0].private_domain
    POSTGRESQL2_HOST   = module.postgresql_server[1].private_domain
    ELASTICSEARCH_HOST = module.elasticsearch_server.private_domain
  })
}

output "indexer_instance_id" {
  value = module.indexer_server.instance_id
}
output "indexer_instance_ami" {
  value = module.indexer_server.instance_ami
}
output "indexer_private_domain" {
  value = module.indexer_server.private_domain
}
output "indexer_private_ip" {
  value = module.indexer_server.private_ip
}
