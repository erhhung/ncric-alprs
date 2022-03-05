locals {
  ssm_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "user_data_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.user_data_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["userdata/*"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.user_data_bucket}/userdata/*"]
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "ssm_instance" {
  name               = "AmazonSSMInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  inline_policy {
    name   = "userdata-bucket-access-policy"
    policy = data.aws_iam_policy_document.user_data_bucket.json
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "ssm_instance" {
  for_each = toset(local.ssm_policy_arns)

  role       = aws_iam_role.ssm_instance.name
  policy_arn = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "ssm_instance" {
  name = "AmazonSSMInstanceProfile"
  role = aws_iam_role.ssm_instance.name
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.config_bucket}"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.config_bucket}/*"]
  }
}

resource "aws_iam_role" "alprs_config" {
  name               = "ALPRSConfigAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json

  inline_policy {
    name   = "userdata-bucket-access-policy"
    policy = data.aws_iam_policy_document.user_data_bucket.json
  }
  inline_policy {
    name   = "config-bucket-access-policy"
    policy = data.aws_iam_policy_document.config_bucket.json
  }
}

resource "aws_iam_role_policy_attachment" "alprs_config" {
  for_each = toset(local.ssm_policy_arns)

  role       = aws_iam_role.alprs_config.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "alprs_config" {
  name = "ALPRSConfigInstanceProfile"
  role = aws_iam_role.alprs_config.name
}
