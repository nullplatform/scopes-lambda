output "dns_record_name" {
  description = "The DNS record name created"
  value       = var.dns_full_domain
}

output "dns_record_type" {
  description = "The type of DNS record created"
  value       = local.dns_use_api_gateway ? "A (alias)" : "CNAME"
}

output "dns_hosted_zone_id" {
  description = "The hosted zone ID used"
  value       = var.dns_hosted_zone_id
}
