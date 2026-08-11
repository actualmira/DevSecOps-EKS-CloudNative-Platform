resource "aws_securityhub_account" "main" {
  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true

  depends_on = [
    aws_config_configuration_recorder_status.main,
    aws_guardduty_detector.main
  ]
}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/5.0.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${var.aws_region}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}

resource "aws_securityhub_product_subscription" "config" {
  product_arn = "arn:aws:securityhub:${var.aws_region}::product/aws/config"
  depends_on  = [aws_securityhub_account.main]
}
