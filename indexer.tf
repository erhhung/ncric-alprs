# t4g.2xlarge: ARM, 8 vCPUs, 32 GiB, EBS only, 5 Gb/s, $.2688/hr

module "indexer" {
  source     = "./modules/instance"
  depends_on = [module.main_vpc]

  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "t4g.2xlarge"
  instance_name    = "Indexer"
  root_volume_size = 48
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.alprs_config.name
  key_name         = aws_key_pair.admin.key_name

  user_data = <<EOT
${templatefile("${path.module}/indexer/boot.tftpl", {
  ENV = var.env
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
EOT
}

output "indexer_instance_id" {
  value = module.indexer.instance_id
}
