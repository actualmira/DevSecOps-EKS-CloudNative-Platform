data "github_user" "reviewer" {
  username = var.github_reviewer
}

# GitHub Environment

resource "github_repository_environment" "production" {
  repository  = var.github_repo
  environment = "production"

  reviewers {
    users = [data.github_user.reviewer.id]
  }

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

# Branch Protection

resource "github_branch_protection" "main" {
  repository_id = var.github_repo
  pattern       = "main"

  required_pull_request_reviews {
    required_approving_review_count = 0
    dismiss_stale_reviews           = true
  }

  required_status_checks {
    strict   = true
    contexts = []
  }

  require_signed_commits          = true
  require_conversation_resolution = true
  enforce_admins                  = false
  allows_force_pushes             = false
  allows_deletions                = false
}

