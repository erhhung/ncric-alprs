locals {
  base_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${local.partition}:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ReadOnlyAccess",
    "arn:${local.partition}:iam::aws:policy/CloudWatchReadOnlyAccess",
    "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
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
  for_each = { for arn in local.base_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.ssm_instance.id
  policy_arn = each.value
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile
resource "aws_iam_instance_profile" "ssm_instance" {
  name = "AmazonSSMInstanceProfile"
  role = aws_iam_role.ssm_instance.id
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

data "aws_iam_policy_document" "email_sender" {
  statement {
    effect    = "Allow"
    actions   = ["ses:SendEmail"]
    resources = [aws_ses_domain_identity.astrometrics.arn]
  }
}

#################### Bastion ####################

resource "aws_iam_role" "alprs_bastion" {
  name               = "ALPRSBastionAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_bastion" {
  for_each = { for arn in local.base_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_bastion.id
  policy_arn = each.value
}

data "aws_iam_policy_document" "alprs_buckets" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
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
resource "aws_iam_role_policy" "alprs_bastion_email_sender" {
  name   = "email-sender-access-policy"
  role   = aws_iam_role.alprs_bastion.id
  policy = data.aws_iam_policy_document.email_sender.json
}

resource "aws_iam_instance_profile" "alprs_bastion" {
  name = "ALPRSBastionInstanceProfile"
  role = aws_iam_role.alprs_bastion.id
}

#################### Service ####################

resource "aws_iam_role" "alprs_service" {
  name               = "ALPRSServiceAccessRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "alprs_service" {
  for_each = { for arn in local.base_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_service.id
  policy_arn = each.value
}

data "aws_iam_policy_document" "backup_bucket" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
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
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
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
  role = aws_iam_role.alprs_service.id
}

#################### EBS ####################

data "aws_iam_policy_document" "service_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.alprs_service.arn]
    }
  }
}

resource "aws_iam_role" "ebs_manager" {
  name                 = "ALPRSEBSManagerRole"
  description          = "Allow services to CRUD temporary EBS volumes."
  assume_role_policy   = data.aws_iam_policy_document.service_trust.json
  max_session_duration = 60 * 60 * 12
}

data "aws_iam_policy_document" "crud_volumes" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeVolumes"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateVolume",
      "ec2:DeleteVolume",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
      "ec2:CreateTags"
    ]
    resources = ["arn:${local.partition}:ec2:${local.region}:${local.account}:*"]
  }
}

resource "aws_iam_role_policy" "ebs_manager_crud_volumes" {
  name   = "crud-ebs-volumes-policy"
  role   = aws_iam_role.ebs_manager.id
  policy = data.aws_iam_policy_document.crud_volumes.json
}

#################### Backup ####################

data "aws_iam_policy_document" "backup_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_backup" {
  name               = "AmazonBackupServiceRole"
  assume_role_policy = data.aws_iam_policy_document.backup_trust.json
}

# https://docs.aws.amazon.com/aws-backup/latest/devguide/security-iam-awsmanpol.html
resource "aws_iam_role_policy_attachment" "aws_backup" {
  role       = aws_iam_role.aws_backup.id
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

#################### SFTP ####################

data "aws_iam_policy_document" "sftp_trust" {
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
  assume_role_policy = data.aws_iam_policy_document.sftp_trust.json
}

data "aws_iam_policy_document" "sftp_bucket1" {
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
  policy = data.aws_iam_policy_document.sftp_bucket1.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_user
# https://docs.aws.amazon.com/transfer/latest/userguide/users-policies.html#users-policies-scope-down
data "aws_iam_policy_document" "sftp_user" {
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::$${transfer:HomeBucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["$${Transfer:HomeFolder}", "$${Transfer:HomeFolder}/*"]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:${local.partition}:s3:::$${transfer:HomeDirectory}/*"]
  }
}

resource "aws_iam_role" "sftp_logger" {
  name               = "AmazonSFTPLoggerRole"
  assume_role_policy = data.aws_iam_policy_document.sftp_trust.json
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
  for_each = { for arn in local.base_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.alprs_worker.id
  policy_arn = each.value
}

data "aws_iam_policy_document" "ingest_buckets" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
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

data "aws_iam_policy_document" "eks_cluster" {
  statement {
    effect = "Allow"
    actions = [
      "eks:ListClusters",
      "eks:DescribeCluster",
    ]
    resources = ["arn:${local.partition}:eks:${local.region}:${local.account}:cluster/*"]
  }
}

data "aws_iam_policy_document" "ecr_repos" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:CreateRepository",
      "ecr:BatchImportUpstreamImage"
    ]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchDeleteImage",
      "ecr:InitiateLayerUpload",
      "ecr:CompleteLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:PutImage"
    ]
    resources = ["arn:${local.partition}:ecr:${local.region}:${local.account}:repository/*"]
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
resource "aws_iam_role_policy" "alprs_worker_eks_cluster" {
  name   = "eks-cluster-access-policy"
  role   = aws_iam_role.alprs_worker.id
  policy = data.aws_iam_policy_document.eks_cluster.json
}
resource "aws_iam_role_policy" "alprs_worker_ecr_repos" {
  name   = "ecr-repos-access-policy"
  role   = aws_iam_role.alprs_worker.id
  policy = data.aws_iam_policy_document.ecr_repos.json
}

resource "aws_iam_instance_profile" "alprs_worker" {
  name = "ALPRSWorkerInstanceProfile"
  role = aws_iam_role.alprs_worker.id
}

#################### LAMBDA ####################

data "aws_iam_policy_document" "lambda_exec" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# lambda exec role to allow sftp_lambda to copy
# files from prod SFTP bucket to dev SFTP bucket

locals {
  sftp_lambda_role_arn = "arn:${var.accounts.prod.partition}:iam::${var.accounts.prod.id}:role/ALPRSSFTPLambdaRole"
  dev_sftp_bucket_arn  = "arn:${var.accounts.dev.partition}:s3:::${replace(var.buckets["sftp"], "-prod", "-dev")}"
}

resource "aws_iam_role" "sftp_lambda" {
  for_each = toset(var.env == "none" ? [""] : [])

  name               = basename(local.sftp_lambda_role_arn)
  assume_role_policy = data.aws_iam_policy_document.lambda_exec.json
}

# ERROR: MalformedPolicyDocument: Partition "aws" is not valid for resource "arn:aws:s3:::alprs-sftp-dev/*"
# https://stackoverflow.com/questions/65924421/accessing-a-commercial-s3-bucket-from-a-govcloud-ec2-instance
data "aws_iam_policy_document" "sftp_lambda" {
  for_each = toset(var.env == "none" ? [""] : [])

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.buckets["sftp"].arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${local.dev_sftp_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "sftp_lambda" {
  for_each = toset(var.env == "none" ? [""] : [])

  name   = "sftp-buckets-access-policy"
  role   = aws_iam_role.sftp_lambda[""].id
  policy = data.aws_iam_policy_document.sftp_lambda[""].json
}

#################### EKS ####################

locals {
  # https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
  eks_cluster_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKSVPCResourceController",
  ]
  # https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html
  eks_node_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]
}

data "aws_iam_policy_document" "eks_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "AmazonEKSClusterRole"
  assume_role_policy = data.aws_iam_policy_document.eks_trust.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  for_each = { for arn in local.eks_cluster_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.eks_cluster.id
  policy_arn = each.value
}

resource "aws_iam_role" "eks_node" {
  name               = "AmazonEKSNodeRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = { for arn in local.eks_node_policy_arns : basename(arn) => arn }

  role       = aws_iam_role.eks_node.id
  policy_arn = each.value
}

data "aws_iam_policy_document" "eks_admin_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        # allow user to Switch Role from AWS Console
        local.account,
        # allow kubectl access from Worker instance
        aws_iam_role.alprs_worker.arn,
      ]
    }
  }
}

resource "aws_iam_role" "eks_admin" {
  name               = "ALPRSEKSAdminRole"
  assume_role_policy = data.aws_iam_policy_document.eks_admin_trust.json
}

data "aws_iam_policy_document" "eks_admin" {
  statement {
    effect = "Allow"
    actions = [
      "eks:*",
      "iam:PassRole",
    ]
    resources = ["*"]
  }
}

# this policy is necessary during EKS cluster creation because
# the EKS admin role will pass the cluster role to EKS service
# but the cluster role has more permissions than the EKS admin
# access policy defined above, and would be restricted without
# the role passer having at least the same level of access
resource "aws_iam_role_policy_attachment" "eks_admin" {
  role       = aws_iam_role.eks_admin.id
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "eks_admin" {
  name   = "eks-admin-access-policy"
  role   = aws_iam_role.eks_admin.id
  policy = data.aws_iam_policy_document.eks_admin.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter
resource "aws_ssm_parameter" "eks_admin_role_arn" {
  name           = "/eks/admin/role/arn"
  type           = "String"
  insecure_value = aws_iam_role.eks_admin.arn
}
