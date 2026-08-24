# Private repo for DVWA 
resource "aws_ecr_repository" "dvwa" {
  name                 = "${var.project}-${var.environment}-dvwa"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-dvwa"
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_ecr_lifecycle_policy" "dvwa" {
  repository = aws_ecr_repository.dvwa.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

data "aws_iam_policy_document" "ecr_repository_policy" {
  statement {
    sid    = "AllowNodePull"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_iam_role.apps_node.arn
      ]
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability"
    ]
  }

  statement {
    sid    = "DenyCrossAccountAccess"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["ecr:*"]

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_ecr_repository_policy" "dvwa" {
  repository = aws_ecr_repository.dvwa.name
  policy     = data.aws_iam_policy_document.ecr_repository_policy.json
}

# PULL-THROUGH CACHE RULE
data "aws_secretsmanager_secret" "dockerhub" {
  name = "ecr-pullthroughcache/${var.project}-${var.environment}-dockerhub"
}

resource "aws_ecr_pull_through_cache_rule" "docker_hub" {
  ecr_repository_prefix = "docker-hub"
  upstream_registry_url = "registry-1.docker.io"
  credential_arn        = data.aws_secretsmanager_secret.dockerhub.arn
}
