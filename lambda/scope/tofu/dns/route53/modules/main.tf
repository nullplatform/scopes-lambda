# Alias record pointing the scope domain at the ALB its listener rule lives on
resource "aws_route53_record" "alb" {
  zone_id = var.dns_hosted_zone_id
  name    = var.dns_full_domain
  type    = "A"

  alias {
    name                   = var.dns_alb_dns_name
    zone_id                = var.dns_alb_zone_id
    evaluate_target_health = false
  }
}
