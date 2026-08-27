resource "aws_ssm_patch_baseline" "eks_nodes" {
  name             = "${var.project}-${var.environment}-eks-patch-baseline"
  operating_system = "AMAZON_LINUX_2023"
  approval_rule {
    approve_after_days = 0
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix"]
    }
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }
  tags = {
    Name        = "${var.project}-${var.environment}-eks-patch-baseline"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_ssm_patch_group" "eks_nodes" {
  baseline_id = aws_ssm_patch_baseline.eks_nodes.id
  patch_group = "${var.project}-${var.environment}-eks-nodes"
}

resource "aws_ssm_maintenance_window" "eks_patching" {
  name     = "${var.project}-${var.environment}-eks-patch-window"
  schedule = "cron(0 2 ? * SUN *)"
  duration = 3
  cutoff   = 1
  tags = {
    Name        = "${var.project}-${var.environment}-eks-patch-window"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_ssm_maintenance_window_target" "eks_nodes" {
  window_id     = aws_ssm_maintenance_window.eks_patching.id
  resource_type = "INSTANCE"
  targets {
    key    = "tag:Patch Group"
    values = [aws_ssm_patch_group.eks_nodes.patch_group]
  }
}

resource "aws_iam_role" "ssm_maintenance" {
  name = "${var.project}-${var.environment}-ssm-maintenance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
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
    Name        = "${var.project}-${var.environment}-ssm-maintenance-role"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_iam_role_policy_attachment" "ssm_maintenance" {
  role       = aws_iam_role.ssm_maintenance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

resource "aws_ssm_maintenance_window_task" "eks_patch_scan" {
  window_id        = aws_ssm_maintenance_window.eks_patching.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.ssm_maintenance.arn
  max_concurrency  = "100%"
  max_errors       = "0"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.eks_nodes.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      parameter {
        name   = "Operation"
        values = ["Scan"]
      }

      output_s3_bucket     = var.ssm_session_logs_bucket_id
      output_s3_key_prefix = "maintenance-window-scans/"

    }
  }
}
