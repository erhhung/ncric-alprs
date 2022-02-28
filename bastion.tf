# t3.micro: x86, 2 vCPUs, 1 GiB, EBS only, 5 Gb/s, $.0104/hr

module "bastion" {
  source     = "./modules/instance"
  depends_on = [module.main_vpc]

  ami_id           = data.aws_ami.amazon_linux2.id
  instance_type    = "t3.micro"
  instance_name    = "Bastion Host"
  root_volume_size = 32
  subnet_id        = module.main_vpc.public_subnet_id
  assign_public_ip = true
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name

  user_data = <<EOT
${templatefile("${path.module}/bastion/boot.tftpl", {
  ENV = var.env
})}
${file("${path.module}/bastion/boot.sh")}
${file("${path.module}/bastion/install.sh")}
EOT
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}
output "bastion_public_ip" {
  value = module.bastion.public_ip
}
