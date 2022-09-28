# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault
resource "aws_backup_vault" "alprs" {
  name = "alprs-backups"
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan
# https://docs.aws.amazon.com/aws-backup/latest/devguide/creating-a-backup-plan.html
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html
# cron fields: min hr dom mon dow yr (IMPORTANT! the time is in UTC, not PST)
resource "aws_backup_plan" "alprs" {
  name = "alprs-backups"

  rule {
    rule_name         = "daily-7day-retention"
    target_vault_name = aws_backup_vault.alprs.name
    schedule          = "cron(20 4 ? * * *)"

    lifecycle {
      delete_after = 7
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_selection
# https://docs.aws.amazon.com/aws-backup/latest/devguide/assigning-resources.html
resource "aws_backup_selection" "ebs" {
  name         = "ebs-volume-backups"
  plan_id      = aws_backup_plan.alprs.id
  iam_role_arn = aws_iam_role.aws_backup.arn

  resources = [
    "arn:${local.partition}:ec2:${local.region}:${local.account}:volume/*",
  ]
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}
