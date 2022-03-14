module "elasticsearch_sg" {
  source = "./modules/secgrp"

  name        = "elasticsearch-sg"
  description = "Allow Elasticsearch/Kibana traffic"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
    ingress_9200 = {
      from_port   = 9200
      to_port     = 9200
      protocol    = "tcp"
      cidr_blocks = local.subnet_cidrs["private"]
    }
    ingress_9300 = {
      from_port   = 9300
      to_port     = 9300
      protocol    = "tcp"
      cidr_blocks = local.subnet_cidrs["private"]
    }
    ingress_443 = {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = local.subnet_cidrs["private"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
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
data "external" "nginx_conf" {
  program = [
    "${path.module}/shared/minconf.sh",
    "${path.module}/elasticsearch/nginx.conf",
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
    path = "elasticsearch/nginx.conf"
    data = data.external.nginx_conf.result.text
    }, {
    path = "elasticsearch/bootstrap.sh"
    data = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/elasticsearch/boot.tftpl", {
    ENV     = var.env
    S3_URL  = local.user_data_s3_url
    ES_YML  = "${local.user_data_s3_url}/elasticsearch/elasticsearch.yml"
    KB_YML  = "${local.user_data_s3_url}/elasticsearch/kibana.yml"
    NG_CONF = "${local.user_data_s3_url}/elasticsearch/nginx.conf"
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/elasticsearch/install.sh")}
${file("${path.module}/shared/epilog.sh")}
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
  source_hash  = md5(each.value.data)
}

locals {
  es_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "elasticsearch"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

# r6g.2xlarge: ARM, 8 vCPUs, 64 GiB, EBS only, 10 Gb/s, $.4032/hr

module "elasticsearch_server" {
  source = "./modules/instance"

  depends_on = [
    module.main_vpc,
    module.elasticsearch_sg,
    aws_s3_object.shared_user_data,
    aws_s3_object.es_user_data,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge"
  instance_name    = "Elasticsearch"
  root_volume_size = 32
  data_volume_size = 256 # 1024*1
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  security_groups  = [module.elasticsearch_sg.id]
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.es_bootstrap)
}

output "elasticsearch_instance_id" {
  value = module.elasticsearch_server.instance_id
}
output "elasticsearch_private_domain" {
  value = module.elasticsearch_server.private_domain
}
output "elasticsearch_private_ip" {
  value = module.elasticsearch_server.private_ip
}
