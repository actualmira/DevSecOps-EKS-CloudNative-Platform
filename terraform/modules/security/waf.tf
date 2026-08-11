resource "aws_wafv2_web_acl" "dvwa" {
  name        = "${var.project}-${var.environment}-dvwa-waf"
  description = "WAF WebACL protecting DVWA from SQL injection, XSS and HTTP floods"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "sql-protection"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-sqli-rule"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "common-threats-protection"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-common-rule"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-limiting"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
        evaluation_window_sec = 60
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-rate-limit-rule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.environment}-dvwa-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-dvwa-waf"
    Environment = var.environment
    Project     = var.project
  }
}
