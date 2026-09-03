# KMS key dedicated to encrypting images at rest in this ECR repo.
# Using a dedicated key (instead of the default AWS-managed key) means
# you control rotation and can audit exactly who has decrypt access.
resource "aws_kms_key" "ecr" {
  description             = "KMS key for ECR image encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

# Create an alias for the KMS key to make it easier to reference in other resources.
# The alias is a human-readable name that points to the KMS key's ARN.
# This alias can be used in the ECR repository's encryption configuration to specify which KMS key to use for encrypting images at rest.
resource "aws_kms_alias" "ecr" {
  name          = "alias/ecr-pipeline-key"
  target_key_id = aws_kms_key.ecr.key_id
}

# The repository itself. Shared by dev/staging/prod — images are
# tagged by commit SHA and promoted between environments, not rebuilt.
# The repository is configured to be immutable, meaning that once an image is pushed with a specific tag, it cannot be overwritten. 
# This prevents accidental overwrites of important images, such as those tagged as "latest". 
# Additionally, image scanning is enabled on push to ensure that any vulnerabilities are detected early in the pipeline. 
#The repository uses the dedicated KMS key for encryption, ensuring that all images are encrypted at rest with a key that you control.
resource "aws_ecr_repository" "app" {
  name                 = "my-app"
  image_tag_mutability = "IMMUTABLE" # prevents overwriting an existing tag, e.g. "latest"
  force_delete         = true # allows terraform destroy to succeed even if images exist

  image_scanning_configuration {
    scan_on_push = true # Trivy in the pipeline is your build-time gate; this is a backstop
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }
}

# Lifecycle policy: expire untagged images after 7 days, and only
# keep the most recent 20 SHA-tagged images. Keeps the repo from
# growing unbounded and reduces the pool of old, unpatched images.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}