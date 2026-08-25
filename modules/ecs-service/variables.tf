variable "environment_name"  { type = string }
variable "vpc_id"            { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string } # only source allowed to reach the service
variable "alb_target_group_arn"   { type = string } # from the ALB, assumed provisioned separately
variable "ecr_repository_url"    { type = string }
variable "image_tag"              { type = string } # the commit SHA being deployed
variable "container_port" {
	type    = number
	default = 8080
}

variable "task_cpu"    { type = string } # e.g. "256" for dev, "1024" for prod
variable "task_memory" { type = string }
variable "desired_count" { type = number }

variable "task_execution_role_arn" { type = string } # pulls image, writes logs
variable "task_role_arn"           { type = string } # app's own runtime AWS permissions