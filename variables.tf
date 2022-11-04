variable "env" {
  description = "Deployment environment: dev/prod"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "Valid values for env: dev/prod."
  }
}

variable "accounts" {
  description = "AWS account info"
  type = object({
    dev = object({
      id        = string
      region    = string
      partition = string # aws
    })
    prod = object({
      id        = string
      region    = string
      partition = string # aws-us-gov
    })
  })
}

variable "aws_provider" {
  description = "AWS provider configuration"
  type = object({
    profile = string
    region  = string
  })
}

variable "buckets" {
  description = "S3 bucket names"
  type = object({
    webapp = string
    config = string
    backup = string
    audit  = string
    media  = string
    sftp   = string
  })
}

variable "instance_types" {
  description = "Host instance types"
  type = object({
    bastion       = string
    postgresql    = string
    elasticsearch = string
    conductor     = string
    datastore     = string
    indexer       = string
    worker        = string
  })

  validation {
    condition = alltrue([
      for type in keys(var.instance_types) : length(regexall(
        type == "bastion" ? "^.+[^g]\\." : "^.+g\\.", var.instance_types[type]
      )) > 0
    ])
    error_message = "Instances other than the Bastion must use ARM-based CPUs."
  }
}

variable "private_ips" {
  description = "Private IP host numbers"
  type = object({
    bastion       = number
    postgresql    = number
    elasticsearch = number
    conductor     = number
    datastore     = number
    indexer       = number
    worker        = number
  })
}

variable "lock_ami_versions" {
  description = "Don't upgrade AMIs if true"
  type        = bool
  default     = false
}

variable "data_volume_sizes" {
  description = "Data volume sizes in GiB"
  type = object({
    postgresql    = number
    elasticsearch = number
  })
}

# https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/enable-access-logs.html
variable "elb_account_id" {
  description = "ELB account ID"
  type        = string
}

variable "ssh_keys" {
  description = "Admin SSH key to import"
  type = list(object({
    key_name   = optional(string)
    public_key = string
  }))
}

variable "sftp_users" {
  description = "Public keys and home dirs of SFTP users"
  type = map(object({
    public_key = string
    home_dir   = string
  }))
}

variable "auth0_user" {
  description = "Headless user for Rundeck jobs"
  type = object({
    email    = string
    password = string
  })
}

variable "flock_user" {
  description = "Access to api.flocksafety.com"
  type = object({
    email    = string
    password = string
  })
}

variable "AUTH0_M2M_CLIENT_ID" {
  description = "Auth0 Machine-to-Machine client ID"
  type        = string
}
variable "AUTH0_M2M_CLIENT_SECRET" {
  description = "Auth0 Machine-to-Machine client secret"
  type        = string
}
variable "AUTH0_SPA_CLIENT_ID" {
  description = "Auth0 Single-Page App client ID"
  type        = string
}
variable "AUTH0_SPA_CLIENT_SECRET" {
  description = "Auth0 Single-Page App client secret"
  type        = string
}
variable "FONTAWESOME_NPM_TOKEN" {
  description = "Font Awesome NPM auth token"
  type        = string
}
variable "GITHUB_ACCESS_TOKEN" {
  description = "GitHub personal access token"
  type        = string
}
variable "MAPBOX_PUBLIC_TOKEN" {
  description = "Mapbox public token"
  type        = string
}
variable "ALPRS_DEVOPS_EMAIL" {
  description = "DevOps e-mail address"
  type        = string
}
variable "ALPRS_SUPPORT_EMAIL" {
  description = "Support e-mail address"
  type        = string
}
