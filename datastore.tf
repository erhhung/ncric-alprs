locals {
  datastore_bootstrap_sh = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/datastore/boot.tftpl", {
  ENV           = var.env
  S3_URL        = local.user_data_s3_url
  GH_TOKEN      = var.GITHUB_ACCESS_TOKEN
  FROM_EMAIL    = local.alprs_sender_email
  BACKUP_BUCKET = var.buckets["backup"]
  CONFIG_BUCKET = var.buckets["config"]
  CONDUCTOR_IP  = module.conductor_server.private_ip
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOT
}

resource "aws_s3_object" "datastore_bootstrap" {
  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/datastore/bootstrap.sh"
  content_type = "text/plain"
  content      = chomp(local.datastore_bootstrap_sh)
  source_hash  = md5(local.datastore_bootstrap_sh)
}

locals {
  datastore_scripts_path = "${path.module}/datastore/scripts"
  datastore_scripts = [
    for path in fileset(local.datastore_scripts_path, "**") : {
      abs = abspath("${local.datastore_scripts_path}/${path}")
      rel = path
    }
  ]
}

resource "aws_s3_object" "datastore_scripts" {
  for_each = { for file in local.datastore_scripts : file.rel => file.abs }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/datastore/scripts/${each.key}"
  content_type = "text/plain"
  source       = each.value
  source_hash  = filemd5(each.value)
}

locals {
  datastore_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "datastore"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "datastore_server" {
  source = "./modules/instance"

  depends_on = [
    aws_s3_object.shared_user_data,
    aws_s3_object.datastore_bootstrap,
    aws_s3_object.datastore_scripts,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["datastore"]
  instance_name    = "Datastore"
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  security_groups  = [module.services_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.datastore_bootstrap)
}

module "datastore_config" {
  source = "./modules/config"

  depends_on = [
    data.external.rhizome_jks,
  ]
  service = "datastore"
  path    = "${path.module}/datastore/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    CONDUCTOR_HOST     = module.conductor_server.private_domain
    POSTGRESQL_HOST    = module.postgresql_server.private_domain
    ELASTICSEARCH_HOST = module.elasticsearch_server.private_domain
  })
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment
resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = module.datastore_server.instance_id
}

output "datastore_instance_id" {
  value = module.datastore_server.instance_id
}
output "datastore_instance_ami" {
  value = module.datastore_server.instance_ami
}
output "datastore_private_domain" {
  value = module.datastore_server.private_domain
}
output "datastore_private_ip" {
  value = module.datastore_server.private_ip
}
