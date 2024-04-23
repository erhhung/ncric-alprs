variable "env" {
  description = "Deployment environment: dev/prod"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "Valid values for env: dev/prod."
  }
}

variable "domain" {
  description = "Hosted zone domain"
  type        = string
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

variable "vpc_ip_prefix" {
  description = "VPC IP address prefix"
  type        = string
  default     = "10.0"
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
    postgresql    = string
    elasticsearch = string
    conductor     = string
    datastore     = string
    indexer       = string
    bastion       = string
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

variable "worker_max_spot_price" {
  description = "Maximum spot price for worker nodes"
  type        = number
}

variable "root_volume_sizes" {
  description = "Root volume sizes in GiB"
  type = object({
    postgresql    = number
    elasticsearch = number
    conductor     = number
    datastore     = number
    indexer       = number
    bastion       = number
    worker        = number
  })
}

variable "data_volume_sizes" {
  description = "Data volume sizes in GiB"
  type = object({
    postgresql1   = number
    postgresql2   = number
    elasticsearch = number
  })
}

variable "private_ips" {
  description = "Private IP host numbers"
  type = object({
    postgresql1   = number
    postgresql2   = number
    elasticsearch = number
    conductor     = number
    datastore     = number
    indexer       = number
    bastion       = number
    worker        = number
  })
}

variable "eks_version" {
  description = "EKS cluster Kubernetes version"
  type        = number
  default     = null # latest
}

variable "eks_public_cidrs" {
  description = "CIDR blocks to allow EKS access"
  type        = list(string)
  default     = null # 0.0.0.0/0

  validation {
    condition = (var.eks_public_cidrs == null || alltrue([
      for cidr in var.eks_public_cidrs :
      length(regexall("^(\\d+\\.){3}\\d+/\\d+$", cidr)) > 0
    ]))
    error_message = "Invalid CIDR block notation."
  }
}

variable "eks_node_types" {
  description = "EKS node group ARM instance types"
  type        = list(string)

  validation {
    condition = alltrue([
      for type in var.eks_node_types :
      length(regexall("^.+g\\.", type)) > 0
    ])
    error_message = "EKS worker nodes must use ARM-based CPUs."
  }
}

variable "eks_node_count" {
  description = "EKS node group size and limits"
  type = object({
    desired = number
    minimum = number
    maximum = number
  })

  validation {
    condition = (
      var.eks_node_count.minimum >= 0 &&
      var.eks_node_count.desired >= var.eks_node_count.minimum &&
      var.eks_node_count.desired <= var.eks_node_count.maximum &&
    var.eks_node_count.maximum <= 10)
    error_message = "Node group size must be between 0 and 10."
  }
}

variable "lock_ami_versions" {
  description = "Prevent unintentional AMI upgrades"
  type        = bool
  default     = false
}

variable "cf_enabled" {
  description = "Enable CloudFront distribution"
  type        = bool
  default     = true
}

variable "geo_restriction" {
  description = "Enable DNS-based geo restrictions"
  type        = bool
  default     = false
}

# https://docs.aws.amazon.com/elasticloadbalancing/latest/classic/enable-access-logs.html
variable "elb_account_id" {
  description = "Account allowed to write ELB logs"
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
variable "AUTH0_WEBHOOK_CLIENT_ID" {
  description = "Auth0 Flock webhook client ID"
  type        = string
}
variable "AUTH0_WEBHOOK_CLIENT_SECRET" {
  description = "Auth0 Flock webhook client secret"
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
variable "GITHUB_ACCESS_TOKEN" {
  description = "GitHub personal access token"
  type        = string
}
variable "GITLAB_ACCESS_TOKEN" {
  description = "GitLab personal access token"
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
