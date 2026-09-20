# TRUST POLICY
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# SNS TOPIC FOR PATCH WEBHOOK FAILURES
resource "aws_sns_topic" "patch_remediation" {
  name = "${var.project}-${var.environment}-patch-remediation"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name        = "${var.project}-${var.environment}-patch-remediation"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_sns_topic_policy" "patch_remediation" {
  arn    = aws_sns_topic.patch_remediation.arn
  policy = data.aws_iam_policy_document.patch_remediation_sns_policy.json
}

data "aws_iam_policy_document" "patch_remediation_sns_policy" {
  statement {
    sid    = "AllowLambdaPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.patch_remediation.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# GITHUB PAT SECRET REFERENCE
data "aws_secretsmanager_secret" "github_pat" {
  name = "github/pat/patch-remediation"
}

# PATCH WEBHOOK IAM ROLE
resource "aws_iam_role" "patch_webhook" {
  name               = "${var.project}-${var.environment}-patch-webhook-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-patch-webhook-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "patch_webhook_policy" {
  statement {
    sid    = "LogToCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    sid    = "AllowSecretsManagerRead"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [data.aws_secretsmanager_secret.github_pat.arn]
  }

  statement {
    sid     = "PublishToSNS"
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.patch_remediation.arn]
  }
}

resource "aws_iam_role_policy" "patch_webhook" {
  name   = "${var.project}-${var.environment}-patch-webhook-policy"
  role   = aws_iam_role.patch_webhook.id
  policy = data.aws_iam_policy_document.patch_webhook_policy.json
}

# PATCH WEBHOOK LAMBDA
data "archive_file" "patch_webhook" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/patch_webhook"
  output_path = "${path.module}/../../lambda/zips/patch_webhook.zip"
}

resource "aws_lambda_function" "patch_webhook" {
  filename         = data.archive_file.patch_webhook.output_path
  function_name    = "${var.project}-${var.environment}-patch-webhook"
  role             = aws_iam_role.patch_webhook.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.patch_webhook.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      GITHUB_SECRET_ARN  = data.aws_secretsmanager_secret.github_pat.arn
      GITHUB_ORG         = var.github_org
      GITHUB_REPO        = var.github_repo
      AWS_REGION_NAME    = var.aws_region
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-patch-webhook"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_permission" "eventbridge_patch_webhook" {
  statement_id  = "AllowEventBridgeInvokePatchWebhook"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.patch_webhook.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ssm_patch_noncompliant.arn
}

resource "aws_lambda_function_event_invoke_config" "patch_webhook_failure" {
  function_name = aws_lambda_function.patch_webhook.function_name

  destination_config {
    on_failure {
      destination = aws_sns_topic.patch_remediation.arn
    }
  }
}
