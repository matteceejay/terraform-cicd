variable "environment_name"  { type = string }
variable "vpc_id"            { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "certificate_arn"   { type = string } # ACM cert — HTTPS only, no plain HTTP to the app
variable "container_port" {
    type    = number
    default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/"
}

# true in prod — makes the ALB immune to accidental terraform destroy.
variable "deletion_protection" {
    type = bool
    default = false 
    }

    variable "hosted_zone_name" {
  description = "Route 53 hosted zone, e.g. example.com"
  type        = string
}

variable "subdomain_name" {
  description = "Full hostname for this environment, e.g. app-dev.example.com"
  type        = string
}