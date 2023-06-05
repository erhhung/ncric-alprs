# The bastion host builds & deploys the AstroMetrics
# frontend to the webapp bucket during bootstrapping
# and runs the lattice-org webapp and Rundeck server

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "bastion_cwagent_json" {
  program = [
    "${path.module}/monitoring/cwagent.sh",
    "bastion",
  ]
}

locals {
  all_bucket_names = join(" ", [
    for key, name in var.buckets : "'${upper(key)}_BUCKET=\"${name}\"'"
  ])
  bastion_user_data = [{
    path = "bastion/cwagent.json"
    data = data.external.bastion_cwagent_json.result.json
    type = "application/json"
    }, {
    path = "bastion/health-check.sh"
    file = "${path.module}/monitoring/health-check.sh"
    }, {
    path = "bastion/.bash_aliases"
    data = <<-EOF
${file("${path.module}/shared/.bash_aliases")}
${file("${path.module}/shared/.bash_aliases_centos")}
EOF
    }, {
    path = "bastion/.bashrc"
    data = file("${path.module}/bastion/.bashrc")
    }, {
    path = "bastion/bootstrap.sh"
    data = <<-EOF
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/bastion/boot.tftpl", {
    ENV              = var.env
    POSTGRESQL1_IP   = module.postgresql_server[0].private_ip
    POSTGRESQL2_IP   = module.postgresql_server[1].private_ip
    ELASTICSEARCH_IP = module.elasticsearch_server.private_ip
    S3_URL           = local.user_data_s3_url
    ALL_BUCKETS      = local.all_bucket_names
    DEVOPS_EMAIL     = var.ALPRS_DEVOPS_EMAIL
})}
${file("${path.module}/bastion/boot.sh")}
${local.webapp_bootstrap}
${local.rundeck_bootstrap}
${file("${path.module}/shared/epilog.sh")}
EOF
}]
}

module "bastion_user_data" {
  source = "./modules/userdata"

  bucket = data.aws_s3_bucket.user_data.id
  files  = local.bastion_user_data
}

locals {
  bastion_bootstrap = <<-EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "bastion"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

module "bastion_host" {
  source = "./modules/instance"

  depends_on = [
    module.shared_user_data,
    module.rundeck_user_data,
    module.bastion_user_data,
  ]
  ami_id           = local.applied_amis["amazon_linux2"].id
  instance_type    = var.instance_types["bastion"]
  instance_name    = local.hosts["bastion"]
  root_volume_size = var.root_volume_sizes["bastion"]
  subnet_id        = module.main_vpc.subnet_ids["private1"]
  private_ip       = local.private_ips["bastion"]
  security_groups  = [module.egress_only_sg.id]
  instance_profile = aws_iam_instance_profile.alprs_bastion.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.bastion_bootstrap)
}

output "bastion_instance_id" {
  value = module.bastion_host.instance_id
}
output "bastion_instance_ami" {
  value = module.bastion_host.instance_ami
}
