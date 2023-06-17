# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
resource "aws_eks_cluster" "alprs" {
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_admin,
  ]
  # NOTE: there is a chance that the aws.eks provider will assume
  # the ALPRSEKSAdminRole before iam:PassRole gets attached to the
  # role, causing cluster creation to fail--just try applying again
  provider = aws.eks

  name     = "alprs"
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_cidrs
  }
}

locals {
  eks = {
    name     = aws_eks_cluster.alprs.name
    version  = aws_eks_cluster.alprs.version
    endpoint = aws_eks_cluster.alprs.endpoint
    ca_cert  = base64decode(aws_eks_cluster.alprs.certificate_authority[0].data)
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth
data "aws_eks_cluster_auth" "alprs" {
  name = aws_eks_cluster.alprs.name
}

# modify the EKS-created cluster SG to allow kubectl access
# to the cluster from the Worker node having private_ssh_sg

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule
resource "aws_security_group_rule" "eks_from_worker" {
  security_group_id        = aws_eks_cluster.alprs.vpc_config[0].cluster_security_group_id
  type                     = "ingress"
  protocol                 = -1
  from_port                = 0
  to_port                  = 0
  source_security_group_id = module.private_ssh_sg.id
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group
# https://docs.aws.amazon.com/eks/latest/APIReference/API_Nodegroup.html
resource "aws_eks_node_group" "alprs" {
  depends_on = [aws_iam_role_policy_attachment.eks_node]

  cluster_name    = local.eks.name
  node_group_name = "alprs-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = local.private_subnet_ids
  instance_types  = var.eks_node_types
  capacity_type   = "SPOT"
  ami_type        = "BOTTLEROCKET_ARM_64"
  disk_size       = 20

  scaling_config {
    desired_size = var.eks_node_count.desired
    min_size     = var.eks_node_count.minimum
    max_size     = var.eks_node_count.maximum
  }
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
  update_config {
    max_unavailable = 1
  }
  force_update_version = true
}

# https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.alprs.identity[0].oidc[0].issuer
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.tls_certificate.eks_oidc.url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}
