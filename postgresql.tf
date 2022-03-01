data "external" "postgresql_conf" {
  program = [
    "${path.module}/shared/minconf.sh",
    "${path.module}/postgresql/postgresql.conf",
  ]
}
data "external" "pg_hba_conf" {
  program = [
    "${path.module}/shared/minconf.sh",
    "${path.module}/postgresql/pg_hba.conf",
  ]
}

# r6g.2xlarge: ARM, 8 vCPUs, 64 GiB, EBS only, 10 Gb/s, $.4032/hr

module "postgresql" {
  source     = "./modules/instance"
  depends_on = [module.main_vpc]

  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge"
  instance_name    = "PostgreSQL"
  root_volume_size = 32
  data_volume_size = 256 # 1024*5
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name

  user_data = <<EOT
${templatefile("${path.module}/postgresql/boot.tftpl", {
  ENV     = var.env
  PG_CONF = data.external.postgresql_conf.result.text
  PG_HBA  = data.external.pg_hba_conf.result.text
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/postgresql/install.sh")}
EOT
}

output "postgresql_instance_id" {
  value = module.postgresql.instance_id
}
output "postgresql_hostname" {
  value = module.postgresql.local_hostname
}
output "postgresql_local_ip" {
  value = module.postgresql.private_ip
}
