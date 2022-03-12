locals {
  bastion_user_data = [{
    path = "bastion/.bash_aliases"
    data = file("${path.module}/bastion/.bash_aliases")
    }, {
    path = "bastion/.bashrc"
    data = file("${path.module}/bastion/.bashrc")
    }, {
    path = "bastion/bootstrap.sh"
    data = <<-EOT
${file("${path.module}/shared/prolog.sh")}
${templatefile("${path.module}/bastion/boot.tftpl", {
    ENV        = var.env
    PG_IP      = module.postgresql_server.private_ip
    ES_IP      = module.elasticsearch_server.private_ip
    USR_S3_URL = local.user_data_s3_url
    })}
${file("${path.module}/bastion/boot.sh")}
${templatefile("${path.module}/webapp/install.tftpl", {
    FA_TOKEN   = var.FONTAWESOME_NPM_TOKEN
    MB_TOKEN   = var.MAPBOX_PUBLIC_TOKEN
    AUTH0_ID   = var.AUTH0_SPA_CLIENT_ID
    APP_URL    = "https://${local.app_domain}"
    API_URL    = "https://${local.api_domain}"
    APP_S3_URL = "s3://${var.buckets["webapp"]}"
})}
${file("${path.module}/webapp/install.sh")}
${file("${path.module}/shared/epilog.sh")}
EOT
}]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "bastion_user_data" {
  for_each = { for object in local.bastion_user_data : basename(object.path) => object }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = "text/plain"
  content      = chomp(each.value.data)
  source_hash  = md5(each.value.data)
}

locals {
  bastion_bootstrap = <<EOT
${templatefile("${path.module}/shared/boot.tftpl", {
  BUCKET = local.user_data_bucket
  HOST   = "bastion"
})}
${file("${path.module}/shared/s3boot.sh")}
EOT
}

# t3.micro: x86, 2 vCPUs, 1 GiB, EBS only, 5 Gb/s, $.0104/hr
# t3.small: x86, 2 vCPUs, 2 GiB, EBS only, 5 Gb/s, $.0208/hr

module "bastion" {
  source = "./modules/instance"

  depends_on = [
    module.main_vpc,
    aws_s3_object.shared_user_data,
    aws_s3_object.bastion_user_data,
  ]
  ami_id           = data.aws_ami.amazon_linux2.id
  instance_type    = "t3.small"
  instance_name    = "Bastion Host"
  root_volume_size = 32
  subnet_id        = module.main_vpc.subnet_ids["public1"]
  assign_public_ip = true
  instance_profile = aws_iam_instance_profile.alprs_buckets.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = chomp(local.bastion_bootstrap)
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}
output "bastion_public_domain" {
  value = module.bastion.public_domain
}
