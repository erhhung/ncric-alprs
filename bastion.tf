locals {
  bastion_user_data = [{
    path = "bastion/.bash_aliases"
    data = file("${path.module}/bastion/.bash_aliases")
    }, {
    path = "bastion/.bashrc"
    data = file("${path.module}/bastion/.bashrc")
    }, {
    path = "bastion/bootstrap.sh"
    data = <<EOT
${templatefile("${path.module}/bastion/boot.tftpl", {
    ENV      = var.env
    S3_URL   = local.user_data_s3_url
    FA_TOKEN = var.FONTAWESOME_NPM_TOKEN
})}
${file("${path.module}/bastion/boot.sh")}
${file("${path.module}/bastion/install.sh")}
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
  etag         = md5(each.value.data)
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
  subnet_id        = module.main_vpc.public_subnet_id
  assign_public_ip = true
  instance_profile = aws_iam_instance_profile.ssm_instance.name
  key_name         = aws_key_pair.admin.key_name
  user_data        = aws_s3_object.bastion_user_data["bootstrap.sh"].content
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}
output "bastion_public_ip" {
  value = module.bastion.public_ip
}
