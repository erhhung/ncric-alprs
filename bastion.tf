module "bastion" {
  source     = "./modules/bastion"
  depends_on = [module.main_vpc.vpc_id]

  instance_type    = "t3.micro"
  volume_size      = 32
  subnet_id        = module.main_vpc.public_subnet_id
  instance_profile = aws_iam_instance_profile.ssm.name
  key_name         = aws_key_pair.admin.key_name
}
