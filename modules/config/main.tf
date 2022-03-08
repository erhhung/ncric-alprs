locals {
  files = [
    for path in fileset(var.path, "**") : {
      abs  = abspath("${var.path}/${path}")
      rel  = path
      ext  = regex("\\.\\w+$", path)
      name = basename(path)
    }
  ]
  contents = {
    for file in local.files : file.name => merge(file, {
      data = contains([".yaml"], file.ext) ? templatefile(file.abs, var.values) : null
    })
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "configs" {
  for_each = local.contents

  bucket       = var.bucket
  key          = "${var.service}/${each.value.rel}"
  content_type = each.value.ext == ".yaml" ? "application/yaml" : "application/octet-stream"
  content      = each.value.data
  source       = each.value.data == null ? each.value.abs : null
  source_hash  = each.value.data == null ? filemd5(each.value.abs) : md5(each.value.data)
}
