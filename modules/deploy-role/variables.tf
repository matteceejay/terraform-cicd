variable "environment_name" {
  description = "dev, staging, or prod"
  type        = string
}

variable "github_repo" {
  description = "org/repo, e.g. matteceejay/terraform-cicd-pipeline"
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