# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1
resource "kubernetes_namespace_v1" "webhook" {
  metadata {
    name = "webhook"
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "webhook_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:GetQueueUrl",
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
    ]
    resources = ["*"]
  }
}

module "webhook_sa" {
  source     = "./modules/service-account"
  depends_on = [kubernetes_namespace_v1.webhook]

  service_account = {
    name      = "flock-webhook-sa"
    namespace = "webhook"

    labels = {
      "app.kubernetes.io/component" = "webhook"
      "app.kubernetes.io/instance"  = "flock-webhook"
      "app.kubernetes.io/name"      = "flock-webhook"
    }
  }
  iam_role_name     = "ALPRSWebhookAccessRole"
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn

  policy_docs = {
    "sqs-read-write-access-policy" = data.aws_iam_policy_document.webhook_sqs.json
  }
}
