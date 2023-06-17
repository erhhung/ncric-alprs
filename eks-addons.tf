module "vpc_cni_sa" {
  source = "./modules/service-account"

  service_account = {
    name      = "aws-node"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/instance" = "aws-vpc-cni"
      "app.kubernetes.io/name"     = "aws-node"
    }
  }
  iam_role_name     = "AmazonEKSVPCCNIRole"
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
  policy_arns       = ["arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon
resource "aws_eks_addon" "vpc_cni" {
  depends_on = [
    module.vpc_cni_sa,
    aws_eks_node_group.alprs,
  ]
  cluster_name             = local.eks.name
  service_account_role_arn = module.vpc_cni_sa.role_arn
  addon_name               = "vpc-cni"
}

resource "aws_eks_addon" "core_dns" {
  depends_on   = [aws_eks_addon.vpc_cni]
  cluster_name = local.eks.name
  addon_name   = "coredns"
}

resource "aws_eks_addon" "kube_proxy" {
  depends_on   = [aws_eks_addon.vpc_cni]
  cluster_name = local.eks.name
  addon_name   = "kube-proxy"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "ebs_csi" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:CreateGrant",
    ]
    resources = ["arn:${local.partition}:kms:*:${local.account}:*"]
  }
}

module "ebs_csi_sa" {
  source = "./modules/service-account"

  service_account = {
    name      = "ebs-csi-controller-sa"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/component" = "csi-driver"
      "app.kubernetes.io/name"      = "aws-ebs-csi-driver"
    }
  }
  iam_role_name     = "AmazonEKSEBSCSIRole"
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn

  policy_arns = [
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
  ]
  policy_docs = {
    "enable-ebs-encryption-policy" = data.aws_iam_policy_document.ebs_csi.json
  }
}

resource "aws_eks_addon" "ebs_csi" {
  depends_on = [
    module.ebs_csi_sa,
    aws_eks_addon.vpc_cni,
  ]
  cluster_name             = local.eks.name
  service_account_role_arn = module.ebs_csi_sa.role_arn
  addon_name               = "aws-ebs-csi-driver"
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/annotations
resource "kubernetes_annotations" "gp2" {
  depends_on = [aws_eks_addon.ebs_csi]

  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = "true"

  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1
resource "kubernetes_storage_class_v1" "gp3" {
  depends_on = [aws_eks_addon.ebs_csi]

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }
}

# install AWS Load Balancer Controller (a.k.a. AWS ALB Ingress Controller) add-on:
# https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html

# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/data_source
data "external" "lb_controller_policy_json" {
  program = [
    "${path.module}/eks/lbctrl.sh",
    local.region,
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy
resource "aws_iam_policy" "lb_controller" {
  name   = "AmazonEKSLoadBalancerControllerPolicy"
  policy = data.external.lb_controller_policy_json.result.json
}

module "lb_controller_sa" {
  source = "./modules/service-account"

  service_account = {
    name      = "aws-load-balancer-controller-sa"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
  }
  iam_role_name     = "AmazonEKSLoadBalancerControllerRole"
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn

  policy_arns = [
    # cannot use "aws_iam_policy.lb_controller.arn" here
    "arn:${local.partition}:iam::${local.account}:policy/AmazonEKSLoadBalancerControllerPolicy",
  ]
}

# https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release
resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  chart      = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = local.eks.name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller-sa"
  }
}
