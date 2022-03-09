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

variable "buckets" {
  type = object({
    webapp = string
    config = string
    audit  = string
    media  = string
    sftp   = string
  })
}

variable "elb_account_id" {
  # https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/enable-access-logs.html
  description = "ELB account ID"
  type        = string
}
variable "ssh_key" {
  description = "Admin SSH key to import"
  type = object({
    key_name   = string
    public_key = string
  })
}

variable "AUTH0_CLIENT_ID" {
  description = "Auth0 client ID"
  type        = string
}
variable "AUTH0_CLIENT_SECRET" {
  description = "Auth0 client secret"
  type        = string
}
variable "FONTAWESOME_NPM_TOKEN" {
  description = "Font Awesome NPM auth token"
  type        = string
}
variable "MAPBOX_PUBLIC_TOKEN" {
  description = "Mapbox public token"
  type        = string
}
