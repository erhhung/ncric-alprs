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

locals {
  pg_user_data = [{
    path = "postgresql/postgresql.conf"
    data = data.external.postgresql_conf.result.text
    }, {
    path = "postgresql/pg_hba.conf"
    data = data.external.pg_hba_conf.result.text
    }, {
    path = "postgresql/bootstrap.sh"
    data = <<EOT
${templatefile("${path.module}/postgresql/boot.tftpl", {
    ENV     = var.env
    S3_URL  = "${local.user_data_s3_url}/userdata"
    PG_CONF = "${local.user_data_s3_url}/userdata/postgresql/postgresql.conf"
    PG_HBA  = "${local.user_data_s3_url}/userdata/postgresql/pg_hba.conf"
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/postgresql/install.sh")}
EOT
}]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "pg_user_data" {
  for_each = { for object in local.pg_user_data : basename(object.path) => object }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = "text/plain"
  content      = chomp(each.value.data)
  etag         = md5(each.value.data)
}

# r6g.2xlarge: ARM, 8 vCPUs, 64 GiB, EBS only, 10 Gb/s, $.4032/hr

module "postgresql" {
  source = "./modules/instance"

  depends_on = [
    module.main_vpc,
    aws_s3_object.shared_user_data,
    aws_s3_object.pg_user_data,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = "r6g.2xlarge"
  instance_name    = "PostgreSQL"
  root_volume_size = 32
  data_volume_size = 256 # 1024*5
  subnet_id        = module.main_vpc.private_subnet_id
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = aws_s3_object.pg_user_data["bootstrap.sh"].content
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
