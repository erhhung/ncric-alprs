variable "env" {
  description = "Deployment environment: dev/prod"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "Valid values for env: dev/prod."
  }
}

variable "aws_provider" {
  description = "AWS provider configuration"
  type = object({
    profile = string
    region  = string
  })
}

variable "ssh_key" {
  description = "Admin SSH key to import"
  type = object({
    key_name   = string
    public_key = string
  })
}
