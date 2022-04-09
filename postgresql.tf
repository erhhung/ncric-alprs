module "postgresql_sg" {
  source = "./modules/secgrp"

  name        = "postgresql-sg"
  description = "Allow PostgreSQL traffic"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
    ingress_5432 = {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = local.subnet_cidrs["private"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
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
    # "alprs.sql" contains the exported EDM (entity
    # data model) that was originally imported from
    # api.openlattice.com by starting the conductor
    # once with the "edmsync" flag
    path = "postgresql/alprs.sql.gz"
    file = "${path.module}/postgresql/alprs.sql.gz"
    data = null
    }, {
    path = "postgresql/bootstrap.sh"
    data = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/postgresql/boot.tftpl", {
    ENV       = var.env
    S3_URL    = local.user_data_s3_url
    APP_URL   = "https://${local.app_domain}"
    PG_CONF   = "${local.user_data_s3_url}/postgresql/postgresql.conf"
    PG_HBA    = "${local.user_data_s3_url}/postgresql/pg_hba.conf"
    ALPRS_SQL = "${local.user_data_s3_url}/postgresql/alprs.sql.gz"
    # passwords created by keys.tf
    alprs_pass    = local.alprs_pass
    atlas_pass    = local.atlas_pass
    BACKUP_BUCKET = var.buckets["backup"]
})}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/postgresql/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOT
}]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "pg_user_data" {
  for_each = { for obj in local.pg_user_data : basename(obj.path) => obj }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = regex("\\.\\w+$", each.value.path) == ".gz" ? "application/gzip" : "text/plain"
  content      = each.value.data == null ? null : chomp(each.value.data)
  source       = each.value.data != null ? null : each.value.file
  source_hash  = each.value.data != null ? md5(each.value.data) : filemd5(each.value.file)
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

module "postgresql_server" {
  source = "./modules/instance"

  depends_on = [
    aws_s3_object.shared_user_data,
    aws_s3_object.pg_user_data,
  ]
  ami_id           = data.aws_ami.ubuntu_20arm.id
  instance_type    = var.instance_types["postgresql"]
  instance_name    = "PostgreSQL"
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  security_groups  = [module.postgresql_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.pg_bootstrap)
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment
resource "aws_volume_attachment" "postgresql_data" {
  volume_id   = aws_ebs_volume.postgresql_data.id
  instance_id = module.postgresql_server.instance_id
  device_name = "/dev/xvdb"
}

output "postgresql_instance_id" {
  value = module.postgresql_server.instance_id
}
output "postgresql_private_domain" {
  value = module.postgresql_server.private_domain
}
output "postgresql_private_ip" {
  value = module.postgresql_server.private_ip
}
