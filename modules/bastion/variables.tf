variable "instance_type" {
  description = "Instance type"
  type        = string
  default     = "t3.micro"
}

variable "volume_size" {
  description = "Root volume size"
  type        = number
  default     = 8
}

variable "subnet_id" {
  description = "VPC subnet ID"
  type        = string
}

variable "instance_profile" {
  description = "Instance profile"
  type        = string
}

variable "key_name" {
  description = "Key pair name"
  type        = string
}
