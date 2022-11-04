variable "name" {
  description = "Security group name"
  type        = string
}

variable "description" {
  description = "Security group description"
  type        = string
}

variable "vpc_id" {
  description = "ID of associated VPC"
  type        = string
}

variable "rules" {
  description = "Security group rules"
  default     = {}

  type = map(object({
    from_port   = number
    to_port     = optional(number)
    protocol    = optional(string, "tcp")
    cidr_blocks = list(string)
  }))

  validation {
    # map keys must begin with "ingress_" or "egress_"
    condition = alltrue([for rule in keys(var.rules) :
      contains(["ingress", "egress"], regex("^[a-z]+", rule))]
    )
    error_message = "Rule names must begin with \"ingress_\" or \"egress_\"."
  }
}
