# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "images" {
  for_each = { for name in fileset("${path.module}/webapp", "*.png") :
    name => abspath("${path.module}/webapp/${name}")
  }

  bucket       = aws_s3_bucket.buckets["webapp"].id
  key          = each.key
  content_type = "image/png"
  source       = each.value
  source_hash  = filemd5(each.value)
}
