# terraform init -backend-config="backend-{env}.conf"
terraform {
  backend "s3" {}
}
