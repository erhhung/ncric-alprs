locals {
  ssm_policy_arns = var.env == "dev" ? [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    ] : [
    "arn:aws-us-gov:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws-us-gov:iam::aws:policy/AmazonSSMManagedInstanceCore",
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

#################### Bastion ####################

resource "aws_iam_role" "alprs_bastion" {
  name               = "ALPRSBastionAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_bastion" {
  for_each = { for arn in local.ssm_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_bastion.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "alprs_buckets" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [for type, _ in var.buckets : aws_s3_bucket.buckets[type].arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [for type, _ in var.buckets : "${aws_s3_bucket.buckets[type].arn}/*"]
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
resource "aws_iam_role_policy" "alprs_bastion_user_data_bucket" {
  name   = "userdata-bucket-access-policy"
  role   = aws_iam_role.alprs_bastion.id
  policy = data.aws_iam_policy_document.user_data_bucket.json
}
resource "aws_iam_role_policy" "alprs_bastion_alprs_buckets" {
  name   = "alprs-buckets-access-policy"
  role   = aws_iam_role.alprs_bastion.id
  policy = data.aws_iam_policy_document.alprs_buckets.json
}

resource "aws_iam_instance_profile" "alprs_bastion" {
  name = "ALPRSBastionInstanceProfile"
  role = aws_iam_role.alprs_bastion.name
}

#################### Service ####################

resource "aws_iam_role" "alprs_service" {
  name               = "ALPRSServiceAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_service" {
  for_each = { for arn in local.ssm_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_service.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "backup_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.buckets["backup"].arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.buckets["backup"].arn}/*"]
  }
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

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
resource "aws_iam_role_policy" "alprs_service_user_data_bucket" {
  name   = "userdata-bucket-access-policy"
  role   = aws_iam_role.alprs_service.id
  policy = data.aws_iam_policy_document.user_data_bucket.json
}
resource "aws_iam_role_policy" "alprs_service_backup_bucket" {
  name   = "backup-bucket-access-policy"
  role   = aws_iam_role.alprs_service.id
  policy = data.aws_iam_policy_document.backup_bucket.json
}
resource "aws_iam_role_policy" "alprs_service_config_bucket" {
  name   = "config-bucket-access-policy"
  role   = aws_iam_role.alprs_service.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

resource "aws_iam_instance_profile" "alprs_service" {
  name = "ALPRSServiceInstanceProfile"
  role = aws_iam_role.alprs_service.name
}

#################### SFTP ####################

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

#################### Worker ####################

resource "aws_iam_role" "alprs_worker" {
  name               = "ALPRSWorkerAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_worker" {
  for_each = { for arn in local.ssm_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_worker.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "ingest_buckets" {
  statement {
    effect  = "Allow"
    actions = ["s3:ListBucket"]
    resources = [
      aws_s3_bucket.buckets["sftp"].arn,
      aws_s3_bucket.buckets["media"].arn,
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.buckets["sftp"].arn}/*",
      "${aws_s3_bucket.buckets["media"].arn}/*",
    ]
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy
resource "aws_iam_role_policy" "alprs_worker_user_data_bucket" {
  name   = "userdata-bucket-access-policy"
  role   = aws_iam_role.alprs_worker.id
  policy = data.aws_iam_policy_document.user_data_bucket.json
}
resource "aws_iam_role_policy" "alprs_worker_ingest_buckets" {
  name   = "ingest-buckets-access-policy"
  role   = aws_iam_role.alprs_worker.id
  policy = data.aws_iam_policy_document.ingest_buckets.json
}
resource "aws_iam_role_policy" "alprs_worker_backup_bucket" {
  name   = "backup-bucket-access-policy"
  role   = aws_iam_role.alprs_worker.id
  policy = data.aws_iam_policy_document.backup_bucket.json
}
resource "aws_iam_role_policy" "alprs_worker_config_bucket" {
  name   = "config-bucket-access-policy"
  role   = aws_iam_role.alprs_worker.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

resource "aws_iam_instance_profile" "alprs_worker" {
  name = "ALPRSWorkerInstanceProfile"
  role = aws_iam_role.alprs_worker.name
}
