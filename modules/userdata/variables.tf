terraform {
  # https://www.terraform.io/language/expressions/type-constraints#experimental-optional-object-type-attributes
  experiments = [module_variable_optional_attrs]
}

variable "bucket" {
  description = "Backend config bucket"
  type        = string
}

variable "files" {
  description = "Files to upload to S3"
  type = list(object({
    # path under "userdata/"
    path = string
    # either "file" or "data"!
    # file: path of local file
    # data: file content string
    file = optional(string)
    data = optional(string)
    # default type: text/plain
    type = optional(string)
  }))
}
