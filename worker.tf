# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "pyntegrationsncric_whl" {
  program = ["${path.module}/worker/mkwhl.sh"]
}

locals {
  worker_user_data = [{
    path = "worker/pyntegrationsncric.whl"
    file = "${path.module}/worker/pyntegrationsncric.whl"
    type = "application/x-wheel+zip"
    }, {
    path = "worker/bootstrap.sh"
    data = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/worker/boot.tftpl", {
    ENV           = var.env
    S3_URL        = local.user_data_s3_url
    SFTP_BUCKET   = var.buckets["sftp"]
    MEDIA_BUCKET  = var.buckets["media"]
    BACKUP_BUCKET = var.buckets["backup"]
    POSTGRESQL_IP = module.postgresql_server.private_ip
    DATASTORE_IP  = module.datastore_server.private_ip
    # public key is created in keys.tf
    rundeck_key = chomp(tls_private_key.rundeck_worker.public_key_openssh)
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/worker/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOT
}]
}

resource "aws_s3_object" "worker_user_data" {
  for_each = { for obj in local.worker_user_data : basename(obj.path) => obj }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = lookup(each.value, "type", "text/plain")
  content      = lookup(each.value, "data", null) == null ? null : chomp(each.value.data)
  source       = lookup(each.value, "file", null) == null ? null : each.value.file
  source_hash  = lookup(each.value, "file", null) != null ? filemd5(each.value.file) : md5(each.value.data)
}

locals {
  worker_bootstrap = <<EOT
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
    aws_s3_object.shared_user_data,
    aws_s3_object.worker_user_data,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = var.instance_types["worker"]
  instance_name    = "Worker"
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  security_groups  = [module.private_ssh_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_worker.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.worker_bootstrap)
}

output "worker_ami_id" {
  value = module.worker_node.ami_id
}
output "worker_ami_name" {
  value = module.worker_node.ami_name
}
output "worker_instance_id" {
  value = module.worker_node.instance_id
}
output "worker_private_domain" {
  value = module.worker_node.private_domain
}
output "worker_private_ip" {
  value = module.worker_node.private_ip
}
