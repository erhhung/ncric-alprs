locals {
  shared_user_data = [{
    path = "shared/.bash_aliases"
    data = file("${path.module}/shared/.bash_aliases")
    }, {
    path = "shared/.gitconfig"
    data = file("${path.module}/shared/.gitconfig")
    }, {
    path = "shared/.screenrc"
    data = file("${path.module}/shared/.screenrc")
    }, {
    path = "shared/.emacs"
    data = file("${path.module}/shared/.emacs")
  }]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "shared_user_data" {
  for_each = { for object in local.shared_user_data : basename(object.path) => object }

  bucket       = data.aws_s3_bucket.user_data.id
  key          = "userdata/${each.value.path}"
  content_type = "text/plain"
  content      = chomp(each.value.data)
  etag         = md5(each.value.data)
}
