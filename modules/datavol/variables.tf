variable "data_volume_name" {
  description = "Data volume name"
  type        = string
}

variable "data_volume_type" {
  description = "Data volume type"
  type        = string
  default     = "gp2"

  validation {
    condition     = contains(["gp2", "gp3"], var.data_volume_type)
    error_message = "Valid values for data_volume_type: gp2/gp3."
  }
}

variable "data_volume_size" {
  description = "Data volume size in GiBs"
  type        = number
}

variable "availability_zone" {
  description = "AZ should match instance"
  type        = string
}

variable "instance_id" {
  description = "ID of instance to attach"
  type        = string
}

variable "device_name" {
  description = "Name of the /dev device"
  type        = string
  default     = "/dev/xvdb"
}
