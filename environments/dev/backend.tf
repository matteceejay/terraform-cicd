terraform {
  backend "s3" {
    bucket       = "terraform-cicd-setup"
    key          = "teracicd/dev/terraform.tfstate" # dev's own state — isolated from staging/prod
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # native S3 locking — no DynamoDB table needed
  }
}