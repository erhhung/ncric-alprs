# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "rdproject_jar" {
  program = ["${path.module}/rundeck/mkjar.sh"]
}

locals {
  rdjar_relpath = "rundeck/astrometrics.rdproject.jar"
  rdjar_abspath = "${path.module}/${local.rdjar_relpath}"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "rdproject_jar" {
  depends_on = [data.external.rdproject_jar]

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${local.rdjar_relpath}"
  content_type = "application/java-archive"
  source       = local.rdjar_abspath
  source_hash  = filemd5(local.rdjar_abspath)
}
