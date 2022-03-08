variable "env" {
  description = "Deployment environment: dev/prod"
  type        = string

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
  webapp_bucket = coalesce(var.webapp_bucket, "alprs-webapp-${var.env}")
  config_bucket = coalesce(var.config_bucket, "alprs-config-${var.env}")
  audit_bucket  = coalesce(var.audit_bucket, "alprs-audit-${var.env}")
  media_bucket  = coalesce(var.media_bucket, "alprs-media-${var.env}")
  sftp_bucket   = coalesce(var.sftp_bucket, "alprs-sftp-${var.env}")
}

variable "AUTH0_CLIENT_ID" {
  description = "Auth0 client ID"
  type        = string
}
variable "AUTH0_CLIENT_SECRET" {
  description = "Auth0 client secret"
  type        = string
}
variable "MAPBOX_PUBLIC_TOKEN" {
  description = "Mapbox public token"
  type        = string
}

variable "FONTAWESOME_NPM_TOKEN" {
  description = "Font Awesome NPM auth token"
  type        = string
}
