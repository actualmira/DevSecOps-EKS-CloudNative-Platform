terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket         = "devsecops-eks-05-26"
    key            = "cicd/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
    kms_key_id     = "alias/terraform-state-key"
  }
}

provider "aws" {
  region = var.aws_region
}

provider "github" {
  owner = var.github_org
}

data "aws_caller_identity" "current" {}

#Locals
locals {
  workflows = {
    eks = {
      workflow_file = "eks.yml"
    }
    network = {
      workflow_file = "network.yml"
    }
    security = {
      workflow_file = "security.yml"
    }
  }
}

#OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name        = "${var.project}-${var.environment}-github-oidc"
    Environment = var.environment
    Project     = var.project
  }
}

#Terraform State Access Policy
resource "aws_iam_policy" "terraform_state_access" {
  name        = "${var.project}-${var.environment}-tf-state-access"
  description = "Read/write Terraform state (S3), locks (DynamoDB), state KMS key"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucket"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = [
          "arn:aws:s3:::devsecops-eks-05-26",
          "arn:aws:s3:::devsecops-eks-05-26/*"
        ]
      },
      {
        Sid    = "StateLock"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/terraform-state-lock"
      },
      {
        Sid    = "StateKMS"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/terraform-state-key"
      }
    ]
  })
}

#Plan Roles
# Any ref, locked to specific workflow file
resource "aws_iam_role" "plan" {
  for_each = local.workflows

  name = "${var.project}-${var.environment}-${each.key}-plan"

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
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub"              = "repo:${var.github_org}/${var.github_repo}:*"
            "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_org}/${var.github_repo}/.github/workflows/${each.value.workflow_file}@*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-${each.key}-plan"
    Environment = var.environment
    Project     = var.project
    Workflow    = each.value.workflow_file
  }
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  for_each = local.workflows

  role       = aws_iam_role.plan[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  for_each = local.workflows

  role       = aws_iam_role.plan[each.key].name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

# Apply Roles
# Main branch only, locked to specific workflow file
resource "aws_iam_role" "apply" {
  for_each = local.workflows

  name = "${var.project}-${var.environment}-${each.key}-apply"

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
            "token.actions.githubusercontent.com:job_workflow_ref" = "${var.github_org}/${var.github_repo}/.github/workflows/${each.value.workflow_file}@refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-${each.key}-apply"
    Environment = var.environment
    Project     = var.project
    Workflow    = each.value.workflow_file
  }
}

# I will streamline the broad administrator access after running IAM Access Analyzer
resource "aws_iam_role_policy_attachment" "apply_admin" {
  for_each = local.workflows

  role       = aws_iam_role.apply[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy_attachment" "apply_state" {
  for_each = local.workflows

  role       = aws_iam_role.apply[each.key].name
  policy_arn = aws_iam_policy.terraform_state_access.arn
}

#GitHub Actions Secrets
resource "github_actions_secret" "plan_role_arn" {
  for_each = local.workflows

  repository      = var.github_repo
  secret_name     = "AWS_ROLE_ARN_${upper(each.key)}_PLAN"
  plaintext_value = aws_iam_role.plan[each.key].arn
}

resource "github_actions_secret" "apply_role_arn" {
  for_each = local.workflows

  repository      = var.github_repo
  secret_name     = "AWS_ROLE_ARN_${upper(each.key)}_APPLY"
  plaintext_value = aws_iam_role.apply[each.key].arn
}

#Outputs
output "plan_role_arns" {
  value = { for k, v in aws_iam_role.plan : k => v.arn }
}

output "apply_role_arns" {
  value = { for k, v in aws_iam_role.apply : k => v.arn }
}

