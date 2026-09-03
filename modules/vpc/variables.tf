variable "environment_name" { type = string }
variable "vpc_cidr"         { type = string } # e.g. 10.0.0.0/16 for dev, 10.1.0.0/16 for staging, 10.2.0.0/16 for prod
variable "azs" {
	type    = list(string)
	default = ["us-east-1a", "us-east-1b"]
}

# Single NAT gateway saves cost (good for dev/staging); prod should set
# this to false so each AZ gets its own NAT — one NAT going down
# shouldn't take out every private subnet's internet access in prod.
variable "single_nat_gateway" { 
    type = bool
    default = true
}