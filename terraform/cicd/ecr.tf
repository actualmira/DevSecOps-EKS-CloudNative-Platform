# ECR Push Policy (Apply role)
resource "aws_iam_policy" "ecr_push" {
  name        = "${var.project}-${var.environment}-ecr-push"
  description = "Minimum permissions for pushing DVWA image to ECR during apply"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}-${var.environment}-dvwa"
      }
    ]
  })
}

# Container Apply Role
resource "aws_iam_role" "container_apply" {
  name = "${var.project}-${var.environment}-container-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"
          }
          StringLike = {
            "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_org}/${var.github_repo}/.github/workflows/appsec.yml@refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-container-apply"
    Environment = var.environment
    Project     = var.project
    Workflow    = "appsec.yml"
  }
}

resource "aws_iam_role_policy_attachment" "container_apply_ecr" {
  role       = aws_iam_role.container_apply.name
  policy_arn = aws_iam_policy.ecr_push.arn
}

# GitHub Actions Secrets
resource "github_actions_secret" "container_role_arn" {
  repository      = var.github_repo
  secret_name     = "AWS_ROLE_ARN_CONTAINER_APPLY"
  value = aws_iam_role.container_apply.arn
}

# Outputs
output "container_apply_role_arn" {
  value = aws_iam_role.container_apply.arn
}
