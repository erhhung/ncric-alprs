variable "service" {
  description = "Name of microservice"
  type        = string

  validation {
    condition     = contains(["conductor", "datastore", "indexer"], var.service)
    error_message = "Valid values for service: conductor/datastore/indexer."
  }
}

variable "path" {
  description = "Path to config files"
  type        = string
}

variable "bucket" {
  description = "Target config bucket"
  type        = string
}

variable "values" {
  description = "Placeholder values"
  type        = map(string)
}
