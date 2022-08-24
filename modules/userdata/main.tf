# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "files" {
  for_each = { for file in var.files : replace(file.path, "/^\\w+\\//", "") => file }

  bucket       = var.bucket
  key          = "userdata/${each.value.path}"
  content_type = lookup(each.value, "type", "text/plain")
  content      = lookup(each.value, "data", null) == null ? null : chomp(each.value.data)
  source       = lookup(each.value, "file", null) == null ? null : each.value.file
  source_hash  = lookup(each.value, "file", null) != null ? filemd5(each.value.file) : md5(each.value.data)
}
