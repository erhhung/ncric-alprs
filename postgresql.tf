module "postgresql_sg" {
  source = "./modules/secgroup"

  name        = "postgresql-sg"
  description = "Allow PostgreSQL traffic"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
    ingress_5432 = {
      from_port   = 5432
      cidr_blocks = local.subnet_cidrs["private"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "postgresql_cwagent_json" {
  program = [
    "${path.module}/monitoring/cwagent.sh",
    "postgresql",
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
  postgresql_scripts_path = "${path.module}/postgresql/scripts"
  postgresql_user_data = flatten([{
    path = "postgresql/cwagent.json"
    data = data.external.postgresql_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "postgresql/postgresql.conf"
    data = data.external.postgresql_conf.result.text
    }, {
    path = "postgresql/pg_hba.conf"
    data = data.external.pg_hba_conf.result.text
    }, {
    path = "postgresql/pgcli.conf"
    file = "${path.module}/postgresql/pgcli.conf"
    }, {
    path = "postgresql/.psqlrc"
    file = "${path.module}/postgresql/.psqlrc"
    }, {
    # "alprs.sql" contains the exported EDM (entity data model) that was
    # originally imported from api.openlattice.com by starting Conductor
    # once with the "edmsync" flag
    path = "postgresql/alprs.sql.gz"
    file = "${path.module}/postgresql/alprs.sql.gz"
    type = "application/gzip"
    }, {
    # "ncric.sql.gz" contains the "integrations.standardized_agency_names"
    # lookup table in the "org_1446ff84711242ec828df181f45e4d20" database
    path = "postgresql/ncric.sql.gz"
    file = "${path.module}/postgresql/ncric.sql.gz"
    type = "application/gzip"
    }, [
    for path in fileset(local.postgresql_scripts_path, "**") : {
      path = "postgresql/scripts/${path}"
      file = "${local.postgresql_scripts_path}/${path}"
    }], {
    path = "postgresql/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/postgresql/boot.tftpl", {
    ENV     = var.env
    S3_URL  = local.user_data_s3_url
    APP_URL = local.app_url
    # passwords are created in keys.tf
    alprs_pass    = local.alprs_pass
    atlas_pass    = local.atlas_pass
    rundeck_pass  = local.rundeck_pass
    BACKUP_BUCKET = var.buckets["backup"]
  })}
${file("${path.module}/shared/boot.sh")}
${file("${path.module}/postgresql/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOF
}])
}

module "postgresql_user_data" {
  source = "./modules/userdata"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.postgresql_user_data
}

locals {
  postgresql_bootstrap = <<-EOT
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
    module.shared_user_data,
    module.postgresql_user_data,
  ]
  ami_id           = local.applied_amis["ubuntu_20arm"].id
  instance_type    = var.instance_types["postgresql"]
  instance_name    = local.hosts["postgresql"]
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  private_ip       = local.private_ips["postgresql"]
  security_groups  = [module.postgresql_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_service.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.postgresql_bootstrap)
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
output "postgresql_instance_ami" {
  value = module.postgresql_server.instance_ami
}
output "postgresql_private_domain" {
  value = module.postgresql_server.private_domain
}
output "postgresql_private_ip" {
  value = module.postgresql_server.private_ip
}
