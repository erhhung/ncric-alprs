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

locals {
  es_user_data = [{
    path = "elasticsearch/elasticsearch.yml"
    data = data.external.elasticsearch_yml.result.text
    }, {
    path = "elasticsearch/kibana.yml"
    data = data.external.kibana_yml.result.text
    }, {
    path = "elasticsearch/bootstrap.sh"
    data = <<EOT
${templatefile("${path.module}/elasticsearch/boot.tftpl", {
    ENV    = var.env
    ES_YML = "${local.user_data_s3_url}/elasticsearch/elasticsearch.yml"
    KB_YML = "${local.user_data_s3_url}/elasticsearch/kibana.yml"
    S3_URL = local.user_data_s3_url
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/elasticsearch/install.sh")}
EOT
}]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "es_user_data" {
  for_each = { for obj in local.es_user_data : basename(obj.path) => obj }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = "text/plain"
  content      = chomp(each.value.data)
  etag         = md5(each.value.data)
}

# r6g.2xlarge: ARM, 8 vCPUs, 64 GiB, EBS only, 10 Gb/s, $.4032/hr

module "elasticsearch_server" {
  source = "./modules/instance"

  depends_on = [
    module.main_vpc,
    aws_s3_object.shared_user_data,
    aws_s3_object.es_user_data,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge"
  instance_name    = "Elasticsearch"
  root_volume_size = 32
  data_volume_size = 256 # 1024*1
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = aws_s3_object.es_user_data["bootstrap.sh"].content
}

output "elasticsearch_instance_id" {
  value = module.elasticsearch_server.instance_id
}
output "elasticsearch_hostname" {
  value = module.elasticsearch_server.local_hostname
}
output "elasticsearch_local_ip" {
  value = module.elasticsearch_server.private_ip
}
