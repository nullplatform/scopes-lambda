# DNS Record for API Gateway (alias record)
resource "aws_route53_record" "api_gateway" {
  count = local.dns_use_api_gateway ? 1 : 0

  zone_id = var.dns_hosted_zone_id
  name    = var.dns_full_domain
  type    = "A"

  alias {
    name                   = local.dns_api_gateway_target
    zone_id                = local.dns_api_gateway_zone
    evaluate_target_health = false
  }
}

# DNS Record for ALB (when not using API Gateway)
# Note: For ALB, we typically need the ALB DNS name passed via context
# This is a placeholder - actual implementation depends on how ALB domain is provided
resource "aws_route53_record" "alb" {
  count = local.dns_use_api_gateway ? 0 : 1

  zone_id = var.dns_hosted_zone_id
  name    = var.dns_full_domain
  type    = "CNAME"
  ttl     = 300

  # For ALB, the target would come from the ALB configuration
  # This needs to be provided via context or as a variable
  records = [try(local.alb_host_header, var.dns_full_domain)]

  lifecycle {
    # Allow external management if needed
    ignore_changes = [records]
  }
}
