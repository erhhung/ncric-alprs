variable "vpc_name" {
  description = "Name of VPC"
  type        = string
  default     = "Main"
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidrs" {
  description = "VPC subnet CIDRs"
  type = object({
    public  = string
    private = string
  })
}
