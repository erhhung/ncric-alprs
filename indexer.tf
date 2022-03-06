locals {
  indexer_bootstrap = <<EOT
${templatefile("${path.module}/indexer/boot.tftpl", {
  ENV    = var.env
  S3_URL = local.user_data_s3_url
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
EOT
}

resource "aws_s3_object" "indexer_bootstrap" {
  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/indexer/bootstrap.sh"
  content_type = "text/plain"
  content      = chomp(local.indexer_bootstrap)
  etag         = md5(local.indexer_bootstrap)
}

# t4g.2xlarge: ARM, 8 vCPUs, 32 GiB, EBS only, 5 Gb/s, $.2688/hr

module "indexer" {
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
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.alprs_config.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = aws_s3_object.indexer_bootstrap.content
}

output "indexer_instance_id" {
  value = module.indexer.instance_id
}
