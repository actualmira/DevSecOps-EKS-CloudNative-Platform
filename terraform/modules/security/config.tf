resource "aws_config_configuration_recorder" "main" {
  name     = "${var.project}-${var.environment}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${var.project}-${var.environment}-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
  
  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_s3_bucket" "config" {
  bucket = "${var.project}-${var.environment}-aws-config"

  tags = {
    Name        = "${var.project}-${var.environment}-aws-config"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.config.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-config-snapshots"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_s3.json
}

data "aws_iam_policy_document" "config_s3" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "config" {
  name = "${var.project}-${var.environment}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-config-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_config_rule" "cloudtrail_enabled" {
  name = "${var.project}-${var.environment}-cloudtrail-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CLOUD_TRAIL_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-cloudtrail-enabled"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_config_config_rule" "vpc_flow_logs_enabled" {
  name = "${var.project}-${var.environment}-vpc-flow-logs-enabled"

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-vpc-flow-logs-enabled"
    Environment = var.environment
    Project     = var.project
  }
}


resource "aws_config_config_rule" "kms_key_rotation_enabled" {
  name = "${var.project}-${var.environment}-kms-key-rotation-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CMK_BACKING_KEY_ROTATION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-kms-key-rotation-enabled"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_config_config_rule" "restricted_ssh" {
  name = "${var.project}-${var.environment}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-restricted-ssh"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_config_config_rule" "restricted_common_ports" {
  name = "${var.project}-${var.environment}-restricted-common-ports"

  source {
    owner             = "AWS"
    source_identifier = "RESTRICTED_INCOMING_TRAFFIC"
  }

  input_parameters = jsonencode({
    blockedPorts = "3306,8200"
  })

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-restricted-common-ports"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_config_config_rule" "eks_secrets_encrypted" {
  name = "${var.project}-${var.environment}-eks-secrets-encrypted"

  source {
    owner             = "AWS"
    source_identifier = "EKS_SECRETS_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-eks-secrets-encrypted"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_config_config_rule" "eks_endpoint_no_public_access" {
  name = "${var.project}-${var.environment}-eks-endpoint-no-public-access"

  source {
    owner             = "AWS"
    source_identifier = "EKS_ENDPOINT_NO_PUBLIC_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-eks-endpoint-no-public-access"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_account_public_access_block" "main" {
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_config_config_rule" "s3_account_public_block" {
  name        = "${var.project}-${var.environment}-s3-account-public-block"
  
  source {
    owner             = "AWS"
    source_identifier = "S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS"
  }

  depends_on = [aws_config_configuration_recorder_status.main]

  tags = {
    Name        = "${var.project}-${var.environment}-s3-account-public-block"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role" "config_s3_remediation" {
  name               = "${var.project}-${var.environment}-config-s3-remediation-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json

  tags = {
    Name        = "${var.project}-${var.environment}-config-s3-remediation-role"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "ssm_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "config_s3_remediation_policy" {
  statement {
    sid    = "AllowSSMAutomation"
    effect = "Allow"
    actions = [
      "ssm:StartAutomationExecution",
      "ssm:GetAutomationExecution"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowS3AccountBlock"
    effect = "Allow"
    actions = [
      "s3:PutAccountPublicAccessBlock",
      "s3:GetAccountPublicAccessBlock"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "config_s3_remediation" {
  name   = "${var.project}-${var.environment}-config-s3-remediation-policy"
  role   = aws_iam_role.config_s3_remediation.id
  policy = data.aws_iam_policy_document.config_s3_remediation_policy.json
}

resource "aws_config_remediation_configuration" "s3_account_public_block" {
  config_rule_name = aws_config_config_rule.s3_account_public_block.name
  target_type      = "SSM_DOCUMENT"
  target_id        = "AWSConfigRemediation-ConfigureS3PublicAccessBlock"
  automatic                  = true
  maximum_automatic_attempts = 5
  retry_attempt_seconds      = 60

  parameter {
    name         = "AccountId"
    static_value = data.aws_caller_identity.current.account_id
  }

  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.config_s3_remediation.arn
  }

  parameter {
    name         = "BlockPublicAcls"
    static_value = "true"
  }

  parameter {
    name         = "BlockPublicPolicy"
    static_value = "true"
  }

  parameter {
    name         = "IgnorePublicAcls"
    static_value = "true"
  }

  parameter {
    name         = "RestrictPublicBuckets"
    static_value = "true"
  }
}
