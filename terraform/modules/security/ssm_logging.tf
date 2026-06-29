resource "aws_s3_bucket" "ssm_session_logs" {
  bucket              = "${var.project}-${var.environment}-ssm-session-logs"
  object_lock_enabled = true

  tags = {
    Name        = "${var.project}-${var.environment}-ssm-session-logs"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket_versioning" "ssm_session_logs" {
  bucket = aws_s3_bucket.ssm_session_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "ssm_session_logs" {
  bucket = aws_s3_bucket.ssm_session_logs.id
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "ssm_session_logs" {
  bucket                  = aws_s3_bucket.ssm_session_logs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_session_logs" {
  bucket = aws_s3_bucket.ssm_session_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.ssm_session_logs.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_session_logs" {
  bucket = aws_s3_bucket.ssm_session_logs.id

  rule {
    id     = "cleanup-expired-session-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_cloudwatch_log_group" "ssm_session_logs" {
  name              = "/${var.project}/${var.environment}/ssm-session-logs"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.ssm_session_logs.arn

  tags = {
    Name        = "${var.project}-${var.environment}-ssm-session-logs"
    Environment = var.environment
    Project     = var.project
  }
}

data "aws_iam_policy_document" "ssm_session_logging" {
  statement {
    sid    = "AllowS3SessionLogWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.ssm_session_logs.arn}/*"]
  }

  statement {
    sid    = "AllowS3BucketAclCheck"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketLocation"
    ]
    resources = [aws_s3_bucket.ssm_session_logs.arn]
  }

  statement {
    sid    = "AllowCloudWatchSessionLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = ["${aws_cloudwatch_log_group.ssm_session_logs.arn}:*"]
  }

  statement {
    sid    = "AllowKMSForSessionLogging"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt"
    ]
    resources = [aws_kms_key.ssm_session_logs.arn]
  }
}

resource "aws_iam_policy" "ssm_session_logging" {
  name   = "${var.project}-${var.environment}-ssm-session-logging-policy"
  policy = data.aws_iam_policy_document.ssm_session_logging.json

  tags = {
    Name        = "${var.project}-${var.environment}-ssm-session-logging-policy"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_ssm_document" "session_manager_preferences" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager logs to S3 and CloudWatch"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.ssm_session_logs.id
      s3EncryptionEnabled         = true
      s3KeyPrefix                 = ""
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.ssm_session_logs.name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = aws_kms_key.ssm_session_logs.arn
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = ""
      shellProfile = {
        linux   = ""
        windows = ""
      }
    }
  })

  tags = {
    Name        = "${var.project}-${var.environment}-ssm-session-preferences"
    Environment = var.environment
    Project     = var.project
  }
}
