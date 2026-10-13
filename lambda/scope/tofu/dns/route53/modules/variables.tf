variable "dns_hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "dns_full_domain" {
  description = "Full domain name of the scope"
  type        = string
}

variable "dns_alb_dns_name" {
  description = "DNS name of the ALB the scope's rule lives on"
  type        = string
}

variable "dns_alb_zone_id" {
  description = "Canonical hosted zone ID of that ALB"
  type        = string
}
