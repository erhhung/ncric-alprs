locals {
  users = concat([
    for name in ["audit", "media"] : {
      name = "alprs-${name}"
      policy = {
        name = "${name}-bucket-access-policy"
        statements = [{
          actions   = ["s3:ListBucket"],
          resources = ["arn:aws:s3:::${local.buckets[name]}"],
          }, {
          actions   = ["s3:GetObject", "s3:PutObject"],
          resources = ["arn:aws:s3:::${local.buckets[name]}/*"],
        }]
      }
    }
    ], [{
      name = "alprs-mail"
      policy = {
        name = "ses-mail-sender-policy"
        statements = [{
          actions   = ["ses:SendRawEmail"],
          resources = ["*"],
        }]
      }
    }
  ])
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user
resource "aws_iam_user" "users" {
  for_each = { for user in local.users : user.name => user }
  name     = each.key
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key
resource "aws_iam_access_key" "users" {
  for_each = { for user in local.users : user.name => user }
  user     = aws_iam_user.users[each.key].name
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document
data "aws_iam_policy_document" "users" {
  for_each = { for user in local.users : user.name => user.policy }

  dynamic "statement" {
    for_each = each.value.statements

    content {
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy
resource "aws_iam_user_policy" "users" {
  for_each = { for user in local.users : user.name => user.policy }

  name   = each.value.name
  user   = aws_iam_user.users[each.key].name
  policy = data.aws_iam_policy_document.users[each.key].json
}
