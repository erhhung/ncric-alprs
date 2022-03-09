module "main_vpc" {
  source = "./modules/vpc"

  subnet_cidrs = {
    public  = ["10.0.10.0/24", "10.0.11.0/24"]
    private = ["10.0.20.0/24", "10.0.21.0/24"]
  }
}

# outputs:
# module.main_vpc.vpc_id
# module.main_vpc.subnet_ids["public1","private1",...]
