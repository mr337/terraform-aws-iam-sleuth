

data "aws_region" "current" {
}

data "aws_iam_account_alias" "current" {
}

#
# Lambda
#
module "iam_sleuth" {
  source = "git@github.com:retentionscience/terraform_aws_lambda_python.git?ref=948f4aa340c9d9346918e3bace7c5a48d0bb4c1f"

  description      = "Audits IAM Access keys for replacement"
  function_name    = "iam_sleuth"
  handler_name     = "handler.handler"
  role_arn         = aws_iam_role.iam_sleuth.arn
  source_code_path = "${path.module}/sleuth/"
  runtime          = "python3.8"
  timeout          = "500" #seconds
  environment = {
    SNS_TOPIC = var.sns_topic_arn
  }
}

#
# Cloudwatch Event
#

resource "aws_cloudwatch_event_rule" "lambda_rule_trigger" {
  name        = "iam-sleuth-trigger"
  description = "Trigger to audit IAM keys"

  schedule_expression = var.schedule

}

resource "aws_cloudwatch_event_target" "sleuth_lambda_target" {
  target_id = "sleuth_lambda_target" // Worked for me after I added `target_id`
  rule      = aws_cloudwatch_event_rule.lambda_rule_trigger.name
  arn       = module.iam_sleuth.arn
}

resource "aws_lambda_permission" "sleuth_lambda_permission" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = module.iam_sleuth.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_rule_trigger.arn
}


#
# IAM
#

data "aws_iam_policy_document" "task_role_policy_doc" {
  # Allow to list and disable keys
  statement {
    actions = [
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys",
      "iam:ListUserTags",
    ]

    resources = ["arn:aws:iam::*:user/*"]
  }

  statement {
    actions = [
      "sns:Publish"
    ]

    resources = [var.sns_topic_arn]
  }

  # Allow to list and disable keys
  statement {
    actions = [
      "iam:ListUsers",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "iam_sleuth" {
  name = "iam_sleuth"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "sleuth_policy" {
  name        = "aws-iam-sleuth-policy"
  description = "Policy for IAM sleuth lambda checker"
  policy      = data.aws_iam_policy_document.task_role_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "test_attach" {
  role       = aws_iam_role.iam_sleuth.name
  policy_arn = aws_iam_policy.sleuth_policy.arn
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.iam_sleuth.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
