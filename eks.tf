# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster
resource "aws_eks_cluster" "alprs" {
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    aws_iam_role_policy_attachment.eks_admin,
  ]

  name     = "alprs"
  version  = var.eks_version
  provider = aws.eks
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_cidrs
  }
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
