locals {
  datastore_bootstrap_sh = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/datastore/boot.tftpl", {
  ENV           = var.env
  S3_URL        = local.user_data_s3_url
  CONFIG_BUCKET = var.buckets["config"]
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
  datastore_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "datastore"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

# r6g.2xlarge: ARM,  8 vCPUs,  64 GiB, EBS only, 10 Gb/s, $.4032/hr
# r6g.4xlarge: ARM, 16 vCPUs, 128 GiB, EBS only, 10 Gb/s, $.8064/hr

module "datastore_server" {
  source = "./modules/instance"

  depends_on = [
    module.main_vpc,
    aws_s3_object.shared_user_data,
    aws_s3_object.datastore_bootstrap,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge" # r6g.4xlarge
  instance_name    = "Datastore"
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  instance_profile = aws_iam_instance_profile.alprs_config.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.datastore_bootstrap)
}

module "datastore_config" {
  source = "./modules/config"

  service = "datastore"
  path    = "${path.module}/datastore/config"
  bucket  = aws_s3_bucket.buckets["config"].id
  values  = local.config_values
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment
resource "aws_lb_target_group_attachment" "api" {
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = module.datastore_server.instance_id
}

output "datastore_instance_id" {
  value = module.datastore_server.instance_id
}
output "datastore_private_domain" {
  value = module.datastore_server.private_domain
}
output "datastore_private_ip" {
  value = module.datastore_server.private_ip
}
