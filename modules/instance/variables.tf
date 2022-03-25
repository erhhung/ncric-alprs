variable "instance_name" {
  description = "Instance name"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string

  validation {
    condition     = length(regexall("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type)) > 0
    error_message = "Invalid instance_type."
  }
}

variable "ami_id" {
  description = "EC2 AMI ID"
  type        = string

  validation {
    condition     = length(regexall("^ami-[a-f0-9]+$", var.ami_id)) > 0
    error_message = "Invalid ami_id."
  }
}

variable "root_volume_type" {
  description = "Root volume type"
  type        = string
  default     = "gp2"

  validation {
    condition     = contains(["gp2", "gp3"], var.root_volume_type)
    error_message = "Valid values for root_volume_type: gp2/gp3."
  }
}

variable "root_volume_size" {
  description = "Root volume size in GiBs"
  type        = number
  default     = 8
}

variable "subnet_id" {
  description = "VPC subnet ID"
  type        = string

  validation {
    condition     = length(regexall("^subnet-[a-f0-9]+$", var.subnet_id)) > 0
    error_message = "Invalid subnet_id."
  }
}

variable "security_groups" {
  description = "IDs of VPC security groups"
  type        = list(string)
  default     = null
}

variable "assign_public_ip" {
  description = "Assign public IP?"
  type        = bool
  default     = false
}

variable "instance_profile" {
  description = "Instance profile"
  type        = string
}

variable "key_name" {
  description = "Key pair name"
  type        = string
}

variable "user_data" {
  description = "Instance launch script"
  type        = string
  default     = ""
}
