# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic
resource "aws_sns_topic" "cloudwatch_alarms" {
  name         = "cloudwatch-alarms"
  display_name = "[alprs${var.env}] CloudWatch Alarms"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy
resource "aws_sns_topic_policy" "cloudwatch_alarms" {
  arn    = aws_sns_topic.cloudwatch_alarms.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "SNS:Publish",
      "SNS:Subscribe",
      "SNS:Receive",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:ListSubscriptionsByTopic",
      "SNS:DeleteTopic",
    ]
    resources = [
      aws_sns_topic.cloudwatch_alarms.arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [local.account]
    }
  }
}

# IMPORTANT! E-mail notifications will not be active until the topic subscription has
# been confirmed manually by clicking on the link in the e-mail sent to the recipient

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription
resource "aws_sns_topic_subscription" "devops_email" {
  protocol  = "email"
  topic_arn = aws_sns_topic.cloudwatch_alarms.arn
  endpoint  = var.ALPRS_DEVOPS_EMAIL
}
