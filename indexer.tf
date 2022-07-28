locals {
  indexer_bootstrap_sh = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/indexer/boot.tftpl", {
  ENV           = var.env
  S3_URL        = local.user_data_s3_url
  GH_TOKEN      = var.GITHUB_ACCESS_TOKEN
  BACKUP_BUCKET = var.buckets["backup"]
  CONFIG_BUCKET = var.buckets["config"]
  DATASTORE_IP  = module.datastore_server.private_ip
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOT
}

resource "aws_s3_object" "indexer_bootstrap" {
  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/indexer/bootstrap.sh"
  content_type = "text/plain"
  content      = chomp(local.indexer_bootstrap_sh)
  source_hash  = md5(local.indexer_bootstrap_sh)
}

locals {
  indexer_scripts_path = "${path.module}/indexer/scripts"
  indexer_scripts = [
    for path in fileset(local.indexer_scripts_path, "**") : {
      path = "${local.indexer_scripts_path}/${path}"
      rel  = path
    }
  ]
}

resource "aws_s3_object" "indexer_scripts" {
  for_each = { for file in local.indexer_scripts : file.rel => file.path }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/indexer/scripts/${each.key}"
  content_type = "text/plain"
  source       = each.value
  source_hash  = filemd5(each.value)
}

locals {
  indexer_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "indexer"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "indexer_server" {
  source = "./modules/instance"

  depends_on = [
    aws_s3_object.shared_user_data,
    aws_s3_object.indexer_bootstrap,
    aws_s3_object.indexer_scripts,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["indexer"]
  instance_name    = "Indexer"
  root_volume_size = 48
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  security_groups  = [module.services_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.indexer_bootstrap)
}

module "indexer_config" {
  source = "./modules/config"

  depends_on = [
    data.external.rhizome_jks,
  ]
  service = "indexer"
  path    = "${path.module}/indexer/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    CONDUCTOR_HOST     = module.conductor_server.private_domain
    POSTGRESQL_HOST    = module.postgresql_server.private_domain
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
