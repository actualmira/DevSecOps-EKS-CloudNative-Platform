output "aws_lbc_role_arn" {
  value       = aws_iam_role.aws_lbc.arn
}

output "loki_role_arn" {
  value       = aws_iam_role.loki.arn
}

output "alertmanager_role_arn" {
  value       = aws_iam_role.alertmanager.arn
}
