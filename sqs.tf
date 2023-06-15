# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue
# https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html
resource "aws_sqs_queue" "webhook_queue" {
  name                       = "webhook-queue"
  max_message_size           = 1024 * 4
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
  message_retention_seconds  = 60 * 60 * 24 * 1
}

# https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html
resource "aws_sqs_queue" "webhook_dlq" {
  name = "webhook-dlq"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_policy
resource "aws_sqs_queue_redrive_policy" "webhook_queue" {
  queue_url = aws_sqs_queue.webhook_queue.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.webhook_dlq.arn
    maxReceiveCount     = 3
  })
}

# for unknown reasons, this fails with:
# Unknown Attribute RedriveAllowPolicy.

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_allow_policy
#resource "aws_sqs_queue_redrive_allow_policy" "webhook_dlq" {
#  queue_url = aws_sqs_queue.webhook_dlq.id
#
#  redrive_allow_policy = jsonencode({
#    redrivePermission = "byQueue",
#    sourceQueueArns   = [aws_sqs_queue.webhook_queue.arn]
#  })
#}
