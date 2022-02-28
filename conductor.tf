# r6g.2xlarge: ARM,  8 vCPUs,  64 GiB, EBS only, 10 Gb/s, $.4032/hr
# r6g.4xlarge: ARM, 16 vCPUs, 128 GiB, EBS only, 10 Gb/s, $.8064/hr

module "conductor" {
  source     = "./modules/instance"
  depends_on = [module.main_vpc]

  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge" # r6g.4xlarge
  instance_name    = "Conductor"
  root_volume_size = 32
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.alprs_config.name
  key_name         = aws_key_pair.admin.key_name

  user_data = <<EOT
${templatefile("${path.module}/conductor/boot.tftpl", {
  ENV = var.env
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/shared/install.sh")}
EOT
}

output "conductor_instance_id" {
  value = module.conductor.instance_id
}
