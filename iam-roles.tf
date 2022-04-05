locals {
  ssm_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
resource "aws_iam_role" "ssm_instance" {
  name               = "AmazonSSMInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

data "aws_iam_policy_document" "user_data_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [data.aws_s3_bucket.user_data.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["userdata/*"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${data.aws_s3_bucket.user_data.arn}/userdata/*"]
  }
}

locals {
  user_data_roles = [
    aws_iam_role.ssm_instance.id,
    aws_iam_role.alprs_config.id,
    aws_iam_role.alprs_buckets.id,
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
resource "aws_iam_role_policy" "user_data_bucket" {
  for_each = toset(local.user_data_roles)

  name   = "userdata-bucket-access-policy"
  role   = each.value
  policy = data.aws_iam_policy_document.user_data_bucket.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment
resource "aws_iam_role_policy_attachment" "ssm_instance" {
  for_each = { for arn in local.ssm_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.ssm_instance.name
  policy_arn = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "ssm_instance" {
  name = "AmazonSSMInstanceProfile"
  role = aws_iam_role.ssm_instance.name
}

resource "aws_iam_role" "alprs_config" {
  name               = "ALPRSConfigAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_config" {
  for_each = { for arn in local.ssm_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_config.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.buckets["config"].arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.buckets["config"].arn}/*"]
  }
}

resource "aws_iam_role_policy" "config_bucket" {
  name   = "config-bucket-access-policy"
  role   = aws_iam_role.alprs_config.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

resource "aws_iam_instance_profile" "alprs_config" {
  name = "ALPRSConfigInstanceProfile"
  role = aws_iam_role.alprs_config.name
}

resource "aws_iam_role" "alprs_buckets" {
  name               = "ALPRSBucketsAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_buckets" {
  for_each = { for arn in local.ssm_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_buckets.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "alprs_buckets" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [for type, _ in var.buckets : aws_s3_bucket.buckets[type].arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for type, _ in var.buckets : "${aws_s3_bucket.buckets[type].arn}/*"]
  }
}

resource "aws_iam_role_policy" "alprs_buckets" {
  name   = "alprs-buckets-access-policy"
  role   = aws_iam_role.alprs_buckets.id
  policy = data.aws_iam_policy_document.alprs_buckets.json
}

resource "aws_iam_instance_profile" "alprs_buckets" {
  name = "ALPRSBucketsInstanceProfile"
  role = aws_iam_role.alprs_buckets.name
}

data "aws_iam_policy_document" "sftp_transfer" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["transfer.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sftp_transfer" {
  name               = "AmazonSFTPTransferRole"
  assume_role_policy = data.aws_iam_policy_document.sftp_transfer.json
}

data "aws_iam_policy_document" "sftp_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.buckets["sftp"].arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.buckets["sftp"].arn}/*"]
  }
}

resource "aws_iam_role_policy" "sftp_bucket" {
  name   = "sftp-bucket-access-policy"
  role   = aws_iam_role.sftp_transfer.id
  policy = data.aws_iam_policy_document.sftp_bucket.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_user
data "aws_iam_policy_document" "sftp_user" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.buckets["sftp"].arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["$${Transfer:UserName}", "$${Transfer:UserName}/*"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.buckets["sftp"].arn}/$${Transfer:UserName}/*"]
  }
}

resource "aws_iam_role" "sftp_logger" {
  name               = "AmazonSFTPLoggerRole"
  assume_role_policy = data.aws_iam_policy_document.sftp_transfer.json
}

data "aws_iam_policy_document" "cloudwatch_logger" {
  statement {
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_role_policy" "sftp_logger" {
  name   = "sftp-logger-access-policy"
  role   = aws_iam_role.sftp_logger.id
  policy = data.aws_iam_policy_document.cloudwatch_logger.json
}
