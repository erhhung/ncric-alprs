data "external" "elasticsearch_yml" {
  program = [
    "${path.module}/shared/minconf.sh",
    "${path.module}/elasticsearch/elasticsearch.yml",
    "ENV=${var.env}",
  ]
}
data "external" "kibana_yml" {
  program = [
    "${path.module}/shared/minconf.sh",
    "${path.module}/elasticsearch/kibana.yml",
    "ENV=${var.env}",
  ]
}

# r6g.2xlarge: ARM, 8 vCPUs, 64 GiB, EBS only, 10 Gb/s, $.4032/hr

module "elasticsearch" {
  source     = "./modules/instance"
  depends_on = [module.main_vpc]

  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge"
  instance_name    = "Elasticsearch"
  root_volume_size = 32
  data_volume_size = 256 # 1024*1
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name

  user_data = <<EOT
${templatefile("${path.module}/elasticsearch/boot.tftpl", {
  ENV    = var.env
  ES_YML = data.external.elasticsearch_yml.result.text
  KB_YML = data.external.kibana_yml.result.text
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/elasticsearch/install.sh")}
EOT
}

output "elasticsearch_instance_id" {
  value = module.elasticsearch.instance_id
}
output "elasticsearch_hostname" {
  value = module.elasticsearch.local_hostname
}
output "elasticsearch_local_ip" {
  value = module.elasticsearch.private_ip
}
