# Roles GitHub Actions assumes to run `terraform` for environments/dev.
# Reuses the account OIDC provider + caller identity already declared
# in oidc-provider.tf.

locals {
  # immutable subject prefix for this repo — same value as build-role.tf
  gh_repo_sub     = "repo:matteceejay@187773256/terraform-cicd@1345632264"
  tf_state_bucket = "terraform-cicd-setup"
  tf_state_key    = "terraform-cicd/dev/*" # matches environments/dev/backend.tf + its .tflock
}

########################################
# plan role — read-only
########################################
data "aws_iam_policy_document" "tf_plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.gh_repo_sub}:pull_request",
        "${local.gh_repo_sub}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "tf_plan" {
  name               = "github-actions-terraform-plan-dev"
  assume_role_policy = data.aws_iam_policy_document.tf_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# state object read/write is needed even by `plan` — it writes the .tflock
data "aws_iam_policy_document" "tf_state_access" {
  statement {
    sid       = "StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.tf_state_bucket}"]
  }
  statement {
    sid       = "StateObjectRW"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.tf_state_bucket}/${local.tf_state_key}"]
  }
}

resource "aws_iam_role_policy" "tf_plan_state" {
  name   = "tf-state-access"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_state_access.json
}

########################################
# apply role — write, environment-gated
########################################
data "aws_iam_policy_document" "tf_apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # only a job that targets the protected "dev-infra" Environment gets
    # this sub claim, and GitHub only issues it AFTER reviewer approval
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.gh_repo_sub}:environment:dev-infra"]
    }
  }
}

resource "aws_iam_role" "tf_apply" {
  name               = "github-actions-terraform-apply-dev"
  assume_role_policy = data.aws_iam_policy_document.tf_apply_trust.json
}

# PowerUser = everything except IAM/Organizations. The modules here also
# create IAM (deploy-role, ecs-task-roles), so IAM is added back below.
# Tighten to a hand-written policy later if you want least privilege.
resource "aws_iam_role_policy_attachment" "tf_apply_poweruser" {
  role       = aws_iam_role.tf_apply.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

data "aws_iam_policy_document" "tf_apply_iam" {
  statement {
    sid    = "ManageServiceIAM"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags", "iam:PassRole",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy",
      "iam:GetPolicyVersion", "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies", "iam:PutRolePolicy",
      "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tf_apply_iam" {
  name   = "manage-service-iam"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply_iam.json
}

resource "aws_iam_role_policy" "tf_apply_state" {
  name   = "tf-state-access"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_state_access.json
}

########################################
# outputs — paste these ARNs into GitHub repo variables (Step 3)
########################################
output "tf_plan_role_arn"  { value = aws_iam_role.tf_plan.arn }
output "tf_apply_role_arn" { value = aws_iam_role.tf_apply.arn }