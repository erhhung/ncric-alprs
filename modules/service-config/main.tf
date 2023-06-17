locals {
  types = {
    yaml       = "application/yaml"
    properties = "application/x-java-properties"
    binary     = "application/octet-stream"
  }
  exts = [for ext, _ in local.types : ".${ext}"]
}

locals {
  files = [
    for path in fileset(var.path, "**") : {
      path = "${var.path}/${path}"
      rel  = path
      ext  = regex("\\.\\w+$", path)
      name = basename(path)
    }
    # ignore dot files like .gitignore
    if length(regexall("^\\.", basename(path))) == 0
  ]
  contents = {
    for file in local.files : file.name => merge(file, {
      data = contains(local.exts, file.ext) ? templatefile(file.path, var.values) : null
    })
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "files" {
  for_each = local.contents

  bucket       = var.bucket
  key          = "${var.service}/${each.value.rel}"
  content_type = lookup(local.types, one(regex("\\.([a-z]+)$", each.value.ext)), local.types.binary)
  content      = each.value.data
  source       = each.value.data == null ? each.value.path : null
  source_hash  = each.value.data == null ? filemd5(each.value.path) : md5(each.value.data)
}
