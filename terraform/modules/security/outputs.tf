output "ssm_session_logging_policy_arn" {
  value       = aws_iam_policy.ssm_session_logging.arn
}

output "dvwa_waf_arn" {
  value       = aws_wafv2_web_acl.dvwa.arn
}

output "loki_s3_bucket_arn" {
  value       = aws_s3_bucket.loki.arn
}

output "loki_kms_key_id" {
  value       = aws_kms_key.loki.key_id
}

output "alertmanager_sns_topic_arn" {
  value       = aws_sns_topic.alertmanager.arn
}
