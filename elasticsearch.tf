module "elasticsearch_sg" {
  source = "./modules/secgroup"

  name        = "elasticsearch-sg"
  description = "Allow Elasticsearch/Kibana traffic"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
    ingress_9200 = {
      from_port   = 9200
      cidr_blocks = local.subnet_cidrs["private"]
    }
    ingress_9300 = {
      from_port   = 9300
      cidr_blocks = local.subnet_cidrs["private"]
    }
    ingress_443 = {
      from_port   = 443
      cidr_blocks = local.subnet_cidrs["private"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "elasticsearch_cwagent_json" {
  program = [
    "${path.module}/monitoring/cwagent.sh",
    "elasticsearch",
  ]
}
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
  elasticsearch_user_data = [{
    path = "elasticsearch/cwagent.json"
    data = data.external.elasticsearch_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "elasticsearch/elasticsearch.yml"
    data = data.external.elasticsearch_yml.result.text
    type = "application/yaml"
    }, {
    path = "elasticsearch/template.json"
    file = "${path.module}/elasticsearch/template.json"
    type = "application/json"
    }, {
    path = "elasticsearch/kibana.yml"
    data = data.external.kibana_yml.result.text
    type = "application/yaml"
    }, {
    path = "elasticsearch/nginx.conf"
    data = data.external.nginx_conf.result.text
    }, {
    path = "elasticsearch/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/elasticsearch/boot.tftpl", {
    ENV           = var.env
    S3_URL        = local.user_data_s3_url
    BACKUP_BUCKET = var.buckets["backup"]
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/elasticsearch/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOF
}]
}

module "elasticsearch_user_data" {
  source = "./modules/userdata"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.elasticsearch_user_data
}

locals {
  elasticsearch_bootstrap = <<-EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "elasticsearch"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "elasticsearch_server" {
  source = "./modules/instance"

  depends_on = [
    module.shared_user_data,
    module.elasticsearch_user_data,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["elasticsearch"]
  instance_name    = local.hosts["elasticsearch"]
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  private_ip       = local.private_ips["elasticsearch"]
  security_groups  = [module.elasticsearch_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.elasticsearch_bootstrap)
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment
resource "aws_volume_attachment" "elasticsearch_data" {
  volume_id   = aws_ebs_volume.elasticsearch_data.id
  instance_id = module.elasticsearch_server.instance_id
  device_name = "/dev/xvdb"
}

output "elasticsearch_instance_id" {
  value = module.elasticsearch_server.instance_id
}
output "elasticsearch_instance_ami" {
  value = module.elasticsearch_server.instance_ami
}
output "elasticsearch_private_domain" {
  value = module.elasticsearch_server.private_domain
}
output "elasticsearch_private_ip" {
  value = module.elasticsearch_server.private_ip
}
