terraform {
  # terraform init -backend-config config/{ENV}.conf
  backend "s3" {
    key = "tfstate/terraform.tfstate"
  }

  # https://www.terraform.io/language/providers/requirements
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.2"
    }
  }
  required_version = ">= 1.1"

  # https://www.terraform.io/language/expressions/type-constraints#experimental-optional-object-type-attributes
  experiments = [module_variable_optional_attrs]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
data "aws_caller_identity" "current" {}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region
data "aws_region" "current" {}

locals {
  account = data.aws_caller_identity.current.account_id
  region  = data.aws_region.current.name

  hosts = {
    postgresql    = "PostgreSQL"
    elasticsearch = "Elasticsearch"
    conductor     = "Conductor"
    datastore     = "Datastore"
    indexer       = "Indexer"
    bastion       = "Bastion Host"
    worker        = "Worker"
  }
}
