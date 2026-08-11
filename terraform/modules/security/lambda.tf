# TRUST POLICY
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# REVOKE IAM SESSION
resource "aws_iam_role" "revoke_iam_session" {
  name               = "${var.project}-${var.environment}-revoke-iam-session-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-revoke-iam-session-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "revoke_iam_session_policy" {
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
    sid    = "RevokeIAMSession"
    effect = "Allow"
    actions = [
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:UpdateAccessKey",
      "iam:ListAccessKeys"
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*",
                 "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*"]
  }

  statement {
    sid     = "PublishToSNS"
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]
  }
}

resource "aws_iam_role_policy" "revoke_iam_session" {
  name   = "${var.project}-${var.environment}-revoke-iam-session-policy"
  role   = aws_iam_role.revoke_iam_session.id
  policy = data.aws_iam_policy_document.revoke_iam_session_policy.json
}

# CloudTrail
resource "aws_iam_role" "remediate_cloudtrail" {
  name               = "${var.project}-${var.environment}-remediate-cloudtrail-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-remediate-cloudtrail-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "remediate_cloudtrail_policy" {
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
    sid    = "RemediateCloudTrail"
    effect = "Allow"
    actions = [
      "cloudtrail:StartLogging",
      "cloudtrail:GetTrailStatus",
      "cloudtrail:DescribeTrails"
    ]
    resources = ["arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/*"]
  }

  statement {
    sid       = "PublishToSNS"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]
  }
}

resource "aws_iam_role_policy" "remediate_cloudtrail" {
  name   = "${var.project}-${var.environment}-remediate-cloudtrail-policy"
  role   = aws_iam_role.remediate_cloudtrail.id
  policy = data.aws_iam_policy_document.remediate_cloudtrail_policy.json
}

#Security Group
resource "aws_iam_role" "remediate_security_group" {
  name               = "${var.project}-${var.environment}-remediate-sg-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-remediate-sg-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "remediate_security_group_policy" {
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
    sid    = "RemediateSecurityGroup"
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:RevokeSecurityGroupIngress"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PublishToSNS"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.security_alerts.arn]
  }
}

resource "aws_iam_role_policy" "remediate_security_group" {
  name   = "${var.project}-${var.environment}-remediate-sg-policy"
  role   = aws_iam_role.remediate_security_group.id
  policy = data.aws_iam_policy_document.remediate_security_group_policy.json
}

# LAMBDA FUNCTIONS
data "archive_file" "revoke_iam_session" {
  type        = "zip"
  source_dir = "${path.module}/../../../lambda/revoke_iam_session"
  output_path = "${path.module}/../../../lambda/revoke_iam_session/handler.zip"
}

data "archive_file" "remediate_cloudtrail" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/remediate_cloudtrail"
  output_path = "${path.module}/../../../lambda/remediate_cloudtrail/handler.zip"
}

data "archive_file" "remediate_security_group" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/remediate_security_group"
  output_path = "${path.module}/../../../lambda/remediate_security_group/handler.zip"
}

resource "aws_lambda_function" "revoke_iam_session" {
  filename         = data.archive_file.revoke_iam_session.output_path
  function_name    = "${var.project}-${var.environment}-revoke-iam-session"
  role             = aws_iam_role.revoke_iam_session.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.revoke_iam_session.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT   = var.environment
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-revoke-iam-session"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "remediate_cloudtrail" {
  filename         = data.archive_file.remediate_cloudtrail.output_path
  function_name    = "${var.project}-${var.environment}-remediate-cloudtrail"
  role             = aws_iam_role.remediate_cloudtrail.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.remediate_cloudtrail.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      CLOUDTRAIL_TRAIL_NAME = "${var.project}-${var.environment}-trail"
      ENVIRONMENT   = var.environment
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-remediate-cloudtrail"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_lambda_function" "remediate_security_group" {
  filename         = data.archive_file.remediate_security_group.output_path
  function_name    = "${var.project}-${var.environment}-remediate-security-group"
  role             = aws_iam_role.remediate_security_group.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.remediate_security_group.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT   = var.environment
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-remediate-security-group"
    Environment = var.environment
    Project     = var.project
  }
}

# LAMBDA PERMISSIONS FOR EVENTBRIDGE
resource "aws_lambda_permission" "eventbridge_revoke_iam" {
  statement_id  = "AllowEventBridgeInvokeRevokeIAM"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.revoke_iam_session.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.iam_compromise.arn
}

resource "aws_lambda_permission" "eventbridge_remediate_cloudtrail" {
  statement_id  = "AllowEventBridgeInvokeRemediateCloudTrail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_cloudtrail.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_critical_cloudtrail.arn
}

resource "aws_lambda_permission" "eventbridge_remediate_sg" {
  statement_id  = "AllowEventBridgeInvokeRemediateSG"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate_security_group.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.config_critical_security_group.arn
}

# On Failure
resource "aws_lambda_function_event_invoke_config" "revoke_iam_failure" {
  function_name = aws_lambda_function.revoke_iam_session.function_name

  destination_config {
    on_failure {
      destination = aws_sns_topic.security_alerts.arn
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "remediate_cloudtrail_failure" {
  function_name = aws_lambda_function.remediate_cloudtrail.function_name

  destination_config {
    on_failure {
      destination = aws_sns_topic.security_alerts.arn
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "remediate_security_group_failure" {
  function_name = aws_lambda_function.remediate_security_group.function_name

  destination_config {
    on_failure {
      destination = aws_sns_topic.security_alerts.arn
    }
  }
}
