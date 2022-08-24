locals {
  subnet_cidrs = {
    public  = ["10.0.10.0/24", "10.0.11.0/24"]
    private = ["10.0.20.0/24", "10.0.21.0/24"]
  }
  # convert host numbers (last octet) to full IP addresses
  private_ips = { for host, ip in var.private_ips : host =>
    cidrhost(local.subnet_cidrs.private[0], ip)
  }
  all_subnet_cidrs = flatten(values(local.subnet_cidrs))
}

module "main_vpc" {
  source = "./modules/vpc"

  subnet_cidrs = local.subnet_cidrs
}

# outputs:
# module.main_vpc.vpc_id
# module.main_vpc.subnet_ids["public1","private1",...]

locals {
  public_subnet_ids = [for name, id in module.main_vpc.subnet_ids :
    id if length(regexall("public", name)) > 0
  ]
  private_subnet_ids = [for name, id in module.main_vpc.subnet_ids :
    id if length(regexall("private", name)) > 0
  ]
}

module "egress_only_sg" {
  source = "./modules/secgroup"

  name        = "egress-only-sg"
  description = "Allow only outbound traffic"
  vpc_id      = module.main_vpc.vpc_id
}

module "private_ssh_sg" {
  source = "./modules/secgroup"

  name        = "private-ssh-sg"
  description = "Allow SSH from instances"
  vpc_id      = module.main_vpc.vpc_id

  rules = {
    ingress_22 = {
      from_port   = 22
      cidr_blocks = local.subnet_cidrs["private"]
    }
  }
}
