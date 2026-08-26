vpc_cidr            = "10.0.0.0/16"
single_nat_gateway  = true
certificate_arn    = "arn:aws:acm:us-east-1:911167920081:certificate/21391baf-f40d-461a-9a19-6fff8a123af0"
hosted_zone_name   = "handart.site"
subdomain_name     = "teracicd-dev.handart.site"
deletion_protection = false

task_cpu      = "256"
task_memory   = "512"
desired_count = 1

github_repo_immutable   = "matteceejay@187773256/terraform-cicd@1345632264"
github_environment_name = "dev"
oidc_provider_arn       = "arn:aws:iam::911167920081:oidc-provider/token.actions.githubusercontent.com"