output "dns_record_name" {
  description = "The DNS record name created"
  value       = aws_route53_record.alb.name
}

output "dns_hosted_zone_id" {
  description = "The hosted zone ID used"
  value       = var.dns_hosted_zone_id
}
