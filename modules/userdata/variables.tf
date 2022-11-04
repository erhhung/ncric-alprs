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
    # file: path to local file
    # data: file content string
    file = optional(string)
    data = optional(string)
    type = optional(string, "text/plain")
  }))
}
