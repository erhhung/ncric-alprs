locals {
  sftp_lambda_path = "${path.module}/lambdas/sftp_lambda"
}

# https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/archive_file
data "archive_file" "sftp_lambda_zip" {
  for_each = toset(var.env == "none" ? [""] : [])

  type        = "zip"
  source_file = "${local.sftp_lambda_path}.py"
  output_path = "${local.sftp_lambda_path}.zip"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function
resource "aws_lambda_function" "sftp_lambda" {
  for_each = toset(var.env == "none" ? [""] : [])

  function_name    = "copy-prod-sftp-to-dev"
  filename         = data.archive_file.sftp_lambda_zip[""].output_path
  source_code_hash = filebase64sha256("${local.sftp_lambda_path}.py")
  handler          = "sftp_lambda.lambda_handler"
  role             = aws_iam_role.sftp_lambda[""].arn
  runtime          = "python3.8"
  timeout          = 10
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification
resource "aws_s3_bucket_notification" "sftp_lambda" {
  for_each = toset(var.env == "none" ? [""] : [])

  bucket = aws_s3_bucket.buckets["sftp"].id

  lambda_function {
    lambda_function_arn = aws_lambda_function.sftp_lambda[""].arn
    events              = ["s3:ObjectCreated:*"]
  }
}
