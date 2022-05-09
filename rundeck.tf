# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "rdproject_jar" {
  program = ["${path.module}/rundeck/mkjar.sh"]
}

locals {
  rd_user_data = [{
    path = "rundeck/astrometrics.rdproject.jar"
    file = "${path.module}/rundeck/astrometrics.rdproject.jar"
    type = "application/java-archive"
  }]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "rd_user_data" {
  for_each   = { for obj in local.rd_user_data : basename(obj.path) => obj }
  depends_on = [data.external.rdproject_jar]

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = each.value.type
  source       = each.value.file
  source_hash  = filemd5(each.value.file)
}
