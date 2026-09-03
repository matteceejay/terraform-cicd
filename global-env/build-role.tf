# Trust policy: only GitHub Actions workflows running on THIS repo,
# and only on the main branch, can assume this role.
data "aws_iam_policy_document" "github_build_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn] # FIXED — was [data.aws], an incomplete reference
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo_immutable}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_build" {
  name               = "github-actions-ecr-build-push"
  assume_role_policy = data.aws_iam_policy_document.github_build_trust.json
}

# Scoped to ONLY what the build stage needs: get an ECR auth token
# (account-wide, required by the API) and push/pull on this one repo.
# No ECS, no other services, no wildcard resources on the ECR actions.
data "aws_iam_policy_document" "github_build_permissions" {
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this specific action does not support resource-level scoping
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage"
    ]
    resources = [aws_ecr_repository.app.arn] # scoped to this one repo, not "*"
  }
}

resource "aws_iam_role_policy" "github_build" {
  name   = "ecr-build-push"
  role   = aws_iam_role.github_build.id
  policy = data.aws_iam_policy_document.github_build_permissions.json
}