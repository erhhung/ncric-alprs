# https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external
data "external" "dashboard_json" {
  program = [
    "${path.module}/monitoring/dashboard.sh",
    var.env, local.region
  ]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard
resource "aws_cloudwatch_dashboard" "astrometrics" {
  dashboard_name = "AstroMetrics"
  dashboard_body = data.external.dashboard_json.result.json
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm
resource "aws_cloudwatch_metric_alarm" "root_disk" {
  for_each = local.hosts

  alarm_name          = "${each.key}-root-disk-usage"
  alarm_description   = "${local.hosts[each.key]} root disk usage above 90%."
  alarm_actions       = [aws_sns_topic.cloudwatch_alarms.arn]
  ok_actions          = [aws_sns_topic.cloudwatch_alarms.arn]
  comparison_operator = "GreaterThanThreshold"
  threshold           = 90
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "ignore"

  metric_query {
    id          = "disk_usage"
    return_data = true

    metric {
      metric_name = "disk_used_percent"
      namespace   = "CWAgent"
      stat        = "Average"
      period      = 300

      dimensions = {
        host   = "alprs${var.env}-${each.key}"
        path   = "/"
        device = "nvme0n1p1"
        fstype = each.key == "bastion" ? "xfs" : "ext4"
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "data_disk" {
  for_each = var.data_volume_sizes

  alarm_name          = "${each.key}-data-disk-usage"
  alarm_description   = "${local.hosts[each.key]} data disk usage above 90%."
  alarm_actions       = [aws_sns_topic.cloudwatch_alarms.arn]
  ok_actions          = [aws_sns_topic.cloudwatch_alarms.arn]
  comparison_operator = "GreaterThanThreshold"
  threshold           = 90
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "ignore"

  metric_query {
    id          = "disk_usage"
    return_data = true

    metric {
      metric_name = "disk_used_percent"
      namespace   = "CWAgent"
      stat        = "Average"
      period      = 300

      dimensions = {
        host   = "alprs${var.env}-${each.key}"
        path   = "/opt/${replace(each.key, "/\\d+$/", "")}"
        device = "nvme1n1"
        fstype = "xfs"
      }
    }
  }
}
