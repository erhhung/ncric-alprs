# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "files" {
  # form resource key by removing leading path component because it's usually included in module name
  for_each = { for file in var.files : replace(file.path, "/^\\w+?(\\d*)\\/(.+)$/", "$2$1") => file }

  bucket                 = var.bucket
  acl                    = "bucket-owner-full-control"
  key                    = "userdata/${each.value.path}"
  content_type           = lookup(each.value, "type", "text/plain")
  content                = lookup(each.value, "data", null) == null ? null : chomp(each.value.data)
  source                 = lookup(each.value, "file", null) == null ? null : each.value.file
  source_hash            = lookup(each.value, "file", null) != null ? filemd5(each.value.file) : md5(each.value.data)
  server_side_encryption = "AES256"
}
