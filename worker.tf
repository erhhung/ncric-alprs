locals {
  wheels = [
    "pyntegrationsncric",
    "olpy",
  ]
  worker_scripts_paths = [{
    path = "${path.module}/shuttle/scripts"
    dest = "shuttle/"
    }, {
    path = "${path.module}/flapper/scripts"
    dest = "flapper/"
  }]
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "worker_cwagent_json" {
  program = ["${path.module}/shared/cwagent.sh"]
}
data "external" "python_wheels" {
  for_each = toset(local.wheels)

  program = [
    "${path.module}/worker/mkwhl.sh",
    each.key, local.api_url, local.region
  ]
}

locals {
  worker_user_data = flatten([[
    for wheel in local.wheels : {
      path = "worker/${wheel}.whl"
      file = "${path.module}/worker/${wheel}.whl"
      type = "application/x-wheel+zip"
    }], [
    for scripts in local.worker_scripts_paths : [
      for path in fileset(scripts.path, "**") : {
        path = "worker/scripts/${lookup(scripts, "dest", "")}${path}"
        file = "${scripts.path}/${path}"
    }]], {
    path = "worker/cwagent.json"
    data = data.external.worker_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "worker/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/worker/boot.tftpl", {
    ENV           = var.env
    S3_URL        = local.user_data_s3_url
    API_URL       = local.api_url
    GH_TOKEN      = var.GITHUB_ACCESS_TOKEN
    SFTP_BUCKET   = var.buckets["sftp"]
    MEDIA_BUCKET  = var.buckets["media"]
    BACKUP_BUCKET = var.buckets["backup"]
    CONFIG_BUCKET = var.buckets["config"]
    POSTGRESQL_IP = module.postgresql_server.private_ip
    DATASTORE_IP  = module.datastore_server.private_ip
    # public key is created in keys.tf
    rundeck_key = chomp(tls_private_key.rundeck_worker.public_key_openssh)
  })}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/worker/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOF
}])
}

module "worker_user_data" {
  source = "./modules/userdata"

  depends_on = [
    data.external.python_wheels,
  ]
  bucket = data.aws_s3_bucket.user_data.id
  files  = local.worker_user_data
}

locals {
  worker_bootstrap = <<-EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "worker"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "worker_node" {
  source = "./modules/instance"

  depends_on = [
    module.shared_user_data,
    module.worker_user_data,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["worker"]
  instance_name    = "Worker"
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  security_groups  = [module.private_ssh_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_worker.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.worker_bootstrap)
}

locals {
  worker_ami = module.worker_node.instance_ami.name
}

module "shuttle_config" {
  source = "./modules/config"

  service = "shuttle"
  path    = "${path.module}/shuttle/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    POSTGRESQL_HOST    = module.postgresql_server.private_domain
    ELASTICSEARCH_HOST = module.elasticsearch_server.private_domain
  })
}

module "flapper_config" {
  source = "./modules/config"

  service = "flapper"
  path    = "${path.module}/flapper/config"
  bucket  = aws_s3_bucket.buckets["config"].id

  values = merge(local.config_values, {
    FLOCK_USER      = var.flock_user.email
    FLOCK_PASSWORD  = var.flock_user.password
    POSTGRESQL_HOST = module.postgresql_server.private_domain
  })
}

output "worker_instance_id" {
  value = module.worker_node.instance_id
}
output "worker_instance_ami" {
  value = module.worker_node.instance_ami
}
output "worker_private_domain" {
  value = module.worker_node.private_domain
}
output "worker_private_ip" {
  value = module.worker_node.private_ip
}
