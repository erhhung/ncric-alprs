data "external" "pg_passwords" {
  program = [
    "${path.module}/shared/pwgen.sh",
    "10", "2",
  ]
}
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
  alprs_pass = data.external.pg_passwords.result.secret1
  atlas_pass = data.external.pg_passwords.result.secret2

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
    S3_URL  = local.user_data_s3_url
    PG_CONF = "${local.user_data_s3_url}/postgresql/postgresql.conf"
    PG_HBA  = "${local.user_data_s3_url}/postgresql/pg_hba.conf"

    alprs_pass = local.alprs_pass
    atlas_pass = local.atlas_pass
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/postgresql/install.sh")}
EOT
}]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "pg_user_data" {
  for_each = { for obj in local.pg_user_data : basename(obj.path) => obj }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = "text/plain"
  content      = chomp(each.value.data)
  source_hash  = md5(each.value.data)
}

locals {
  pg_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "postgresql"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

# r6g.2xlarge: ARM, 8 vCPUs, 64 GiB, EBS only, 10 Gb/s, $.4032/hr

module "postgresql_server" {
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
  user_data        = chomp(local.pg_bootstrap)
}

output "postgresql_user_logins" {
  value = {
    alprs_user = local.alprs_pass
    atlas_user = local.atlas_pass
  }
  sensitive = true
}

output "postgresql_instance_id" {
  value = module.postgresql_server.instance_id
}
output "postgresql_hostname" {
  value = module.postgresql_server.local_hostname
}
output "postgresql_local_ip" {
  value = module.postgresql_server.private_ip
}
