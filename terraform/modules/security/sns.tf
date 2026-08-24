resource "aws_sns_topic" "security_alerts" {
  name              = "${var.project}-${var.environment}-security-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name        = "${var.project}-${var.environment}-security-alerts"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn    = aws_sns_topic.security_alerts.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowLambdaPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# AlertManager
resource "aws_sns_topic" "alertmanager" {
  name              = "${var.project}-${var.environment}-alertmanager-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name        = "${var.project}-${var.environment}-alertmanager-alerts"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_sns_topic_policy" "alertmanager" {
  arn    = aws_sns_topic.alertmanager.arn
  policy = data.aws_iam_policy_document.alertmanager_sns_policy.json
}

data "aws_iam_policy_document" "alertmanager_sns_policy" {
  statement {
    sid    = "AllowAlertManagerPublish"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alertmanager.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}
