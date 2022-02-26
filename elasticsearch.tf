module "elasticsearch" {
  source     = "./modules/instance"
  depends_on = [module.main_vpc]

  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge"
  instance_name    = "Elasticsearch"
  root_volume_size = 32
  data_volume_size = 16 # 1024*1
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name

  user_data = <<EOT
${templatefile("${path.module}/elasticsearch/boot.tftpl", {
  ENV = var.env
})}
${file("${path.module}/shared/boot.sh")}
EOT
}

output "elasticsearch_instance_id" {
  value = module.elasticsearch.instance_id
}
