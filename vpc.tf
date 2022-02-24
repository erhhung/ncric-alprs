module "main_vpc" {
  source = "./modules/vpc"

  subnet_cidrs = {
    public  = "10.0.1.0/24"
    private = "10.0.2.0/24"
  }
}
