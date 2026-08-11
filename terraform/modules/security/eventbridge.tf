# GUARDDUTY OUTPUT ON IAM COMPROMISE
resource "aws_cloudwatch_event_rule" "iam_compromise" {
  name        = "${var.project}-${var.environment}-iam-compromise"
  description = "Triggers IAM session revocation when credential is compromised"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        "CredentialAccess:IAMUser/CompromisedCredentials",
        "UnauthorizedAccess:IAMUser/ResourceCredentialExfiltration.OutsideAWS"
      ]
    }
  })

  tags = {
    Name        = "${var.project}-${var.environment}-iam-compromise"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_event_target" "revoke_iam_session" {
  rule = aws_cloudwatch_event_rule.iam_compromise.name
  arn  = aws_lambda_function.revoke_iam_session.arn
}

# GUARDDUTY IMMEDIATE ALERT
resource "aws_cloudwatch_event_rule" "guardduty_immediate_alert" {
  name        = "${var.project}-${var.environment}-guardduty-immediate-alert"
  description = "Alert for critical GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        "Policy:IAMUser/RootCredentialUsage",
        "Policy:IAMUser/ShortTermRootCredentialUsage",
        "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS",
        "PrivilegeEscalation:Kubernetes/AnomalousBehavior.WorkloadDeployed!PrivilegedContainer",
        "Backdoor:EC2/C&CActivity.B",
        "CryptoCurrency:EC2/BitcoinTool.B",
        "Trojan:EC2/DNSDataExfiltration",
        "Trojan:EC2/DGADomainRequest.B",
        "Impact:EC2/BitcoinDomainRequest.Reputation",
        "Impact:EC2/MaliciousDomainRequest.Reputation"
      ]
    }
  })

  tags = {
    Name        = "${var.project}-${var.environment}-guardduty-immediate-alert"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_event_target" "guardduty_immediate_alert" {
  rule = aws_cloudwatch_event_rule.guardduty_immediate_alert.name
  arn  = aws_sns_topic.security_alerts.arn
}


# CONFIG CRITICAL CLOUDTRAIL
resource "aws_cloudwatch_event_rule" "config_critical_cloudtrail" {
  name        = "${var.project}-${var.environment}-config-critical-cloudtrail"
  description = "Triggers the main CloudTrail to be re-enabled when disabled"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
      configRuleName = [
        "${var.project}-${var.environment}-cloudtrail-enabled"
      ]
      resourceId = [
        "${var.project}-${var.environment}-trail"
      ]
    }
  })

  tags = {
    Name        = "${var.project}-${var.environment}-config-critical-cloudtrail"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_event_target" "remediate_cloudtrail" {
  rule = aws_cloudwatch_event_rule.config_critical_cloudtrail.name
  arn  = aws_lambda_function.remediate_cloudtrail.arn
}

# CONFIG CRITICAL SECURITY GROUP
resource "aws_cloudwatch_event_rule" "config_critical_security_group" {
  name        = "${var.project}-${var.environment}-config-critical-sg"
  description = "Triggers security group remediation on open sensitive ports"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
      configRuleName = [
        "${var.project}-${var.environment}-restricted-ssh",
        "${var.project}-${var.environment}-restricted-common-ports"
      ]
    }
  })

  tags = {
    Name        = "${var.project}-${var.environment}-config-critical-sg"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_event_target" "remediate_security_group" {
  rule = aws_cloudwatch_event_rule.config_critical_security_group.name
  arn  = aws_lambda_function.remediate_security_group.arn
}

# CONFIG HIGH SEVERITY 
resource "aws_cloudwatch_event_rule" "config_high" {
  name        = "${var.project}-${var.environment}-config-high"
  description = "Alerts on Config violations to require review"

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
      configRuleName = [
        "${var.project}-${var.environment}-vpc-flow-logs-enabled",
        "${var.project}-${var.environment}-kms-key-rotation-enabled",
        "${var.project}-${var.environment}-eks-secrets-encrypted",
        "${var.project}-${var.environment}-eks-endpoint-no-public-access",
      ]
    }
  })

  tags = {
    Name        = "${var.project}-${var.environment}-config-high"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_cloudwatch_event_target" "config_high_alert" {
  rule = aws_cloudwatch_event_rule.config_high.name
  arn  = aws_sns_topic.security_alerts.arn
}
