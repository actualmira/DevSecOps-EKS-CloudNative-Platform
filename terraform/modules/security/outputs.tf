output "cloudtrail_kms_key_arn" {
  description = "ARN of the KMS key used for CloudTrail encryption"
  value       = aws_kms_key.cloudtrail.arn
}

output "vault_unseal_kms_key_arn" {
  description = "ARN of the KMS key used for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.arn
}

output "ssm_session_logging_policy_arn" {
  description = "ARN of the IAM policy granting permissions for SSM session logging to S3/CloudWatch"
  value       = aws_iam_policy.ssm_session_logging.arn
}
output "eks_secrets_kms_key_arn" {
  description = "ARN of the KMS key used for EKS etcd secrets envelope encryption"
  value       = aws_kms_key.eks_secrets.arn
}
