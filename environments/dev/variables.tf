variable "vpc_cidr"            { type = string }
variable "single_nat_gateway"  { type = bool }
variable "certificate_arn"    { type = string }
variable "hosted_zone_name"   { type = string }
variable "subdomain_name"     { type = string }
variable "deletion_protection" { type = bool }

variable "task_cpu"      { type = string }
variable "task_memory"   { type = string }
variable "desired_count" { type = number }

variable "github_repo"             { type = string }
variable "github_environment_name" { type = string }
variable "oidc_provider_arn"       { type = string }