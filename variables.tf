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

variable "webapp_bucket" {
  description = "Webapp bucket name"
  type        = string
  default     = null
}

variable "config_bucket" {
  description = "Config bucket name"
  type        = string
  default     = null
}

variable "audit_bucket" {
  description = "Audit bucket name"
  type        = string
  default     = null
}

variable "media_bucket" {
  description = "Media bucket name"
  type        = string
  default     = null
}

variable "sftp_bucket" {
  description = "SFTP bucket name"
  type        = string
  default     = null
}

locals {
  # work around variable not allowed in variable default value
  webapp_bucket = var.webapp_bucket == null ? "alprs-webapp-${var.env}" : var.webapp_bucket
  config_bucket = var.config_bucket == null ? "alprs-config-${var.env}" : var.config_bucket
  audit_bucket  = var.audit_bucket == null ? "alprs-audit-${var.env}" : var.audit_bucket
  media_bucket  = var.media_bucket == null ? "alprs-media-${var.env}" : var.media_bucket
  sftp_bucket   = var.sftp_bucket == null ? "alprs-sftp-${var.env}" : var.sftp_bucket
}
