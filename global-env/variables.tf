variable "github_repo_immutable" {
  description = "Full immutable subject in owner@id/repo@id form, e.g. OWNER@OWNER_ID/REPO@REPO_ID — see README note on the immutable subject claim format"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket holding Terraform state (shared with environments/*/backend.tf)"
  type        = string
}
