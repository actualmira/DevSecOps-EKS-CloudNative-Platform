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

#Vault
resource "aws_kms_key" "vault_unseal" {
  description             = "KMS key for Vault auto-unseal"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-${var.environment}-vault-unseal-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "vault_unseal" {
  name          = "alias/${var.project}-${var.environment}-vault-unseal"
  target_key_id = aws_kms_key.vault_unseal.key_id
}

#ectd
resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS etcd secrets envelope encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-${var.environment}-eks-secrets-key"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project}-${var.environment}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
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
        Sid    = "Allow CloudWatch Logs to use the key"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
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
    sid    = "Allow AWS Config to use the key"
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
  description             = "KMS key for AWS Config configuration snapshots"
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
