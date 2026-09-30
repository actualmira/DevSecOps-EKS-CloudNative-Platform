# EKS Node Rolling Update Policy
resource "aws_iam_policy" "eks_node_update" {
  name        = "${var.project}-${var.environment}-eks-node-update"
  description = "Minimum permissions for patching workflow to trigger EKS node rolling update"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSNodeUpdate"
        Effect = "Allow"
        Action = [
          "eks:UpdateNodegroupVersion",
          "eks:DescribeNodegroup",
          "eks:DescribeCluster"
        ]
        Resource = [
          "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.project}-${var.environment}-cluster",
          "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:nodegroup/${var.project}-${var.environment}-cluster/*/*"
        ]
      },
      {
        Sid      = "DescribeInstance"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      }
    ]
  })
}

# Patching Workflow Role
resource "aws_iam_role" "patching" {
  name = "${var.project}-${var.environment}-patching-apply"

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
            "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_org}/${var.github_repo}/.github/workflows/patching.yml@refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-patching-apply"
    Environment = var.environment
    Project     = var.project
    Workflow    = "patching.yml"
  }
}

resource "aws_iam_role_policy_attachment" "patching_eks" {
  role       = aws_iam_role.patching.name
  policy_arn = aws_iam_policy.eks_node_update.arn
}

# GitHub Actions Secret
resource "github_actions_secret" "patching_role_arn" {
  repository      = var.github_repo
  secret_name     = "AWS_ROLE_ARN_PATCHING_APPLY"
  value = aws_iam_role.patching.arn
}

# Output
output "patching_role_arn" {
  value = aws_iam_role.patching.arn
}
