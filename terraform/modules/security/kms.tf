data "aws_caller_identity" "current" {}

#Cloudtrail
resource "aws_kms_key" "cloudtrail" {
  description             = "Encryption Key for CloudTrail Logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Permission for IAM Users"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Encrypt CloudTrail Logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-cloudtrail-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/${var.project}-${var.environment}-cloudtrail-key"
  target_key_id = aws_kms_key.cloudtrail.key_id
}


#session logging
resource "aws_kms_key" "ssm_session_logs" {
  description             = "KMS key for SSM session log encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Permission for IAM Users"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/${var.project}/${var.environment}/ssm-session-logs"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-ssm-session-logs-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "ssm_session_logs" {
  name          = "alias/${var.project}-${var.environment}-ssm-session-logs"
  target_key_id = aws_kms_key.ssm_session_logs.key_id
}

#Config
data "aws_iam_policy_document" "config_kms_policy" {
  statement {
    sid    = "Permission for IAM Users"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "Allow AWS Config"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey*",
      "kms:Decrypt"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "config" {
  description             = "KMS key for AWS Config"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.config_kms_policy.json

  tags = {
    Name        = "${var.project}-${var.environment}-config-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "config" {
  name          = "alias/${var.project}-${var.environment}-config"
  target_key_id = aws_kms_key.config.key_id
}

# Loki
resource "aws_kms_key" "loki" {
  description             = "KMS key for Loki S3 log encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Permission for IAM Users"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-loki-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "loki" {
  name          = "alias/${var.project}-${var.environment}-loki-key"
  target_key_id = aws_kms_key.loki.key_id
}
