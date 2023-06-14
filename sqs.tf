# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
# https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html
resource "aws_sqs_queue" "webhook_queue" {
  name                       = "webhook-queue"
  max_message_size           = 1024 * 4
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
  message_retention_seconds  = 60 * 60 * 24 * 1
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = 3
  })
}

locals {
  webhook_queue_arn = "arn:${local.partition}:sqs:${local.region}:${local.account}:webhook-queue"
}

# https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html
resource "aws_sqs_queue" "webhook_dlq" {
  name = "webhook-dlq"
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    # https://github.com/hashicorp/terraform-provider-aws/issues/22577
    #sourceQueueArns = [aws_sqs_queue.webhook_queue.arn]
    sourceQueueArns = [local.webhook_queue_arn]
  })
}
