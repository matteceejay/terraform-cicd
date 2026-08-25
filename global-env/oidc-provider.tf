data "aws_caller_identity" "current" {}

# NOT creating this — a GitHub OIDC provider is scoped to the AWS account,
# not to any one project. If ResumePortal or pet_clinic_cicd already
# registered this URL, this project should reuse that same provider
# rather than fail trying to create a duplicate.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}