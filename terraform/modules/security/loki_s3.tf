# loki s3 
resource "aws_s3_bucket" "loki" {
  # checkov:skip=CKV_AWS_21:Loki log is append-only data and the storage uses lifecycle expiration for retention. 
  # checkov:skip=CKV_AWS_145:Encryption configured via separate aws_s3_bucket_server_side_encryption_configuration resource
  # checkov:skip=CKV_AWS_19:Encryption configured via separate aws_s3_bucket_server_side_encryption_configuration resource
  bucket = "${var.project}-${var.environment}-loki-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project}-${var.environment}-loki-logs"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.loki.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
  }
}
