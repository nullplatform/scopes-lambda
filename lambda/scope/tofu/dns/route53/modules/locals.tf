locals {
  # Module identifier
  dns_module_name = "dns/route53"

  # Determine if we're using API Gateway or ALB based on which locals are available
  # API Gateway provides: api_gateway_target_domain, api_gateway_target_zone_id
  # ALB: we create a CNAME to the ALB domain

  # Check if API Gateway target is available (set by api_gateway module)
  dns_use_api_gateway = try(local.api_gateway_target_domain, "") != ""

  # For API Gateway - use alias record
  dns_api_gateway_target = try(local.api_gateway_target_domain, "")
  dns_api_gateway_zone   = try(local.api_gateway_target_zone_id, "")

  # For ALB - get the ALB DNS name from the listener (would need to be passed differently)
  # For simplicity, ALB domains typically use CNAME records

  # Cross-module outputs
  dns_record_name = var.dns_full_domain
}
