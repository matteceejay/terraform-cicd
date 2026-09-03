data "aws_ecr_repository" "app" {
  name = "my-app" # the shared repo from global/, looked up (not recreated) here
}

module "vpc" {
  source = "../../modules/vpc"

  environment_name   = "dev"
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway # fine for dev — cost over redundancy here
}

module "alb" {
  source = "../../modules/alb"

  environment_name    = "dev"
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  certificate_arn     = var.certificate_arn
  hosted_zone_name    = var.hosted_zone_name
  subdomain_name      = var.subdomain_name
  deletion_protection = var.deletion_protection # false in dev — you'll want true for prod
}

module "task_roles" {
  source = "../../modules/ecs-task-roles"

  environment_name = "dev"
}

module "ecs_service" {
  source = "../../modules/ecs-service"

  environment_name      = "dev"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_security_group_id = module.alb.security_group_id
  alb_target_group_arn  = module.alb.target_group_arn
  ecr_repository_url    = data.aws_ecr_repository.app.repository_url

  image_tag = "latest-known-good" # placeholder — the pipeline updates this via ecs:UpdateService, not here

  task_cpu      = var.task_cpu # smallest Fargate size in dev — dev doesn't need more
  task_memory   = var.task_memory
  desired_count = var.desired_count # single task in dev is fine, no HA requirement here

  task_execution_role_arn = module.task_roles.execution_role_arn
  task_role_arn           = module.task_roles.task_role_arn
}

module "deploy_role" {
  source = "../../modules/deploy-role"

  environment_name        = "dev"
  github_repo_immutable   = var.github_repo_immutable # CHANGED — was github_repo = var.github_repo
  github_environment_name = var.github_environment_name
  oidc_provider_arn       = var.oidc_provider_arn

  ecs_cluster_arn         = module.ecs_service.cluster_arn
  ecs_service_arn         = module.ecs_service.service_arn
  task_execution_role_arn = module.task_roles.execution_role_arn
  task_role_arn           = module.task_roles.task_role_arn
}