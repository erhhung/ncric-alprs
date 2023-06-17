variable "service_account" {
  description = "Service account name and namespace"
  type = object({
    name      = string
    namespace = string
    labels    = optional(map(string))
  })
}

variable "iam_role_name" {
  description = "Name of the IAM role"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OpenID Connect provider"
  type        = string

  validation {
    condition     = length(regexall("^arn:.*:oidc-provider\\/.+$", var.oidc_provider_arn)) > 0
    error_message = "Invalid OIDC provider ARN."
  }
}

variable "policy_arns" {
  description = "ARNs of managed IAM policies to attach to the IAM role"
  type        = list(string)
  default     = []
}

variable "policy_docs" {
  description = "JSON docs of inline policies to attach to the IAM role"
  type        = map(string) # map key = policy name
  default     = {}
}
