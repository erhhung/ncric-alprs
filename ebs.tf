# data volume attachments are defined alongside instances
# so that instances can be re-created without losing data

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume
resource "aws_ebs_volume" "postgresql_data" {
  type              = "gp3"
  size              = var.data_volume_sizes["postgresql"]
  availability_zone = "${local.region}a" # private1 subnet
  throughput        = 500
  encrypted         = true

  tags = {
    Name   = "PostgreSQL Data"
    Backup = "true"
  }
}

resource "aws_ebs_volume" "elasticsearch_data" {
  type              = "gp3"
  size              = var.data_volume_sizes["elasticsearch"]
  availability_zone = "${local.region}a" # private1 subnet
  encrypted         = true

  tags = {
    Name   = "Elasticsearch Data"
    Backup = "true"
  }
}
