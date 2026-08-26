variable "environment_name" {
  description = "dev, staging, or prod"
  type        = string
}

variable "github_repo_immutable" { # RENAMED — was "github_repo"
  description = "Full immutable subject in owner@id/repo@id form, e.g. matteceejay@187773256/terraform-cicd@1345632264"
  type        = string
}

variable "github_environment_name" {
  description = "Name of the GitHub Environment (must match .github settings, e.g. Production)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider created in global/"
  type        = string
}

variable "ecs_cluster_arn" { type = string }
variable "ecs_service_arn" { type = string }
variable "task_execution_role_arn" { type = string }
variable "task_role_arn" { type = string }