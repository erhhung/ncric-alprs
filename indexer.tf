locals {
  indexer_bootstrap_sh = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/indexer/boot.tftpl", {
  ENV           = var.env
  S3_URL        = local.user_data_s3_url
  CONFIG_BUCKET = var.buckets["config"]
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
  indexer_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "indexer"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

# t4g.2xlarge: ARM, 8 vCPUs, 32 GiB, EBS only, 5 Gb/s, $.2688/hr

module "indexer_server" {
  source = "./modules/instance"

  depends_on = [
    module.main_vpc,
    aws_s3_object.shared_user_data,
    aws_s3_object.indexer_bootstrap,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "t4g.2xlarge"
  instance_name    = "Indexer"
  root_volume_size = 48
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  instance_profile = aws_iam_instance_profile.alprs_config.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.indexer_bootstrap)
}

module "indexer_config" {
  source = "./modules/config"

  service = "indexer"
  path    = "${path.module}/indexer/config"
  bucket  = aws_s3_bucket.buckets["config"].id
  values  = local.config_values
}

output "indexer_instance_id" {
  value = module.indexer_server.instance_id
}
output "indexer_private_domain" {
  value = module.indexer_server.private_domain
}
output "indexer_private_ip" {
  value = module.indexer_server.private_ip
}
