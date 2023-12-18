# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external
data "external" "datastore_cwagent_json" {
  program = [
    "${path.module}/monitoring/cwagent.sh",
    "shared", "HOST=datastore"
  ]
}

locals {
  datastore_scripts_path = "${path.module}/datastore/scripts"
  datastore_user_data = flatten([[
    for path in fileset(local.datastore_scripts_path, "**") : {
      path = "datastore/scripts/${path}"
      file = "${local.datastore_scripts_path}/${path}"
    }], {
    path = "datastore/cwagent.json"
    data = data.external.datastore_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "datastore/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/datastore/boot.tftpl", {
    ENV           = var.env
    S3_URL        = local.user_data_s3_url
    GITHUB_TOKEN  = var.GITHUB_ACCESS_TOKEN
    FROM_EMAIL    = local.alprs_sender_email
    BACKUP_BUCKET = var.buckets["backup"]
    CONFIG_BUCKET = var.buckets["config"]
    CONDUCTOR_IP  = module.conductor_server.private_ip
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOF
  }])
}

module "datastore_user_data" {
  source = "./modules/user-data"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.datastore_user_data
}

locals {
  datastore_bootstrap = <<-EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "datastore"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "datastore_server" {
  source = "./modules/ec2-instance"

  depends_on = [
    module.shared_user_data,
    module.datastore_user_data,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["datastore"]
  instance_name    = local.hosts["datastore"]
  root_volume_size = var.root_volume_sizes["datastore"]
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  private_ip       = local.private_ips["datastore"]
  security_groups  = [module.services_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.datastore_bootstrap)
}

module "datastore_config" {
  source = "./modules/service-config"

  depends_on = [
    data.external.rhizome_jks,
  ]
  service = "datastore"
  path    = "${path.module}/datastore/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    CONDUCTOR_HOST     = module.conductor_server.private_domain
    POSTGRESQL1_HOST   = module.postgresql_server[0].private_domain
    POSTGRESQL2_HOST   = module.postgresql_server[1].private_domain
    ELASTICSEARCH_HOST = module.elasticsearch_server.private_domain
  })
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
