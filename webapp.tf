locals {
  webapp_bootstrap = <<-EOT
${templatefile("${path.module}/webapp/install.tftpl", {
  FA_TOKEN      = var.FONTAWESOME_NPM_TOKEN
  GH_TOKEN      = var.GITHUB_ACCESS_TOKEN
  MB_TOKEN      = var.MAPBOX_PUBLIC_TOKEN
  AUTH0_ID      = var.AUTH0_SPA_CLIENT_ID
  SUPPORT_EMAIL = var.ALPRS_SUPPORT_EMAIL
  APP_URL       = "https://${local.app_domain}"
  API_URL       = "https://${local.api_domain}"
})}
${file("${path.module}/webapp/install.sh")}
EOT
}

locals {
  webapp_images_path = "${path.module}/webapp"
  webapp_images = {
    for name in fileset(local.webapp_images_path, "*.png") :
    name => "${local.webapp_images_path}/${name}"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object
resource "aws_s3_object" "images" {
  for_each = local.webapp_images

  bucket       = aws_s3_bucket.buckets["webapp"].id
  key          = each.key
  content_type = "image/png"
  source       = each.value
  source_hash  = filemd5(each.value)
}
