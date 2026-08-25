# Looked up by name rather than hardcoding a zone ID — keeps the module
# portable if the zone ID ever changes (e.g. domain re-registered).
data "aws_route53_zone" "this" {
  name         = var.hosted_zone_name
  private_zone = false
}

# ALIAS, not a CNAME — ALIAS records are Route 53-native, work at the
# zone apex if ever needed, and cost nothing per query. evaluate_target_health
# means Route 53 stops resolving to this ALB if all its targets go unhealthy.
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.subdomain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}