# Trust policy keyed on GitHub's ENVIRONMENT claim, not just repo/branch.
# When a workflow job targets a protected GitHub Environment (one with
# required reviewers configured), the OIDC token's "sub" claim changes
# to include "environment:<name>" — and GitHub only ISSUES that token
# after approval. So this role literally cannot be assumed until
# someone clicks approve — the enforcement lives in AWS, not just the
# workflow YAML.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:${var.github_environment_name}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "github-actions-deploy-${var.environment_name}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

# Only what's needed to roll out a new task definition revision and
# update the service — no cluster creation, no networking changes,
# no access to any other environment's cluster/service.
data "aws_iam_policy_document" "permissions" {
  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:UpdateService"
    ]
    resources = [var.ecs_cluster_arn, var.ecs_service_arn]
  }

  statement {
    sid    = "RegisterTaskDef"
    effect = "Allow"
    actions = ["ecs:RegisterTaskDefinition"]
    resources = ["*"] # this action doesn't support resource-level restriction in IAM
  }

  # Lets ECS use these two roles for the task — but ONLY these two,
  # and only when the thing requesting it is the ECS tasks service.
  # Without the PassedToService condition, this would let the deploy
  # role hand off ANY role it can pass — a common privilege-escalation gap.
  statement {
    sid    = "PassTaskRoles"
    effect = "Allow"
    actions = ["iam:PassRole"]
    resources = [var.task_execution_role_arn, var.task_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "ecs-deploy-${var.environment_name}"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.permissions.json
}