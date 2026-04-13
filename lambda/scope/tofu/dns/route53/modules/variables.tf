variable "dns_hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "dns_domain" {
  description = "Base domain name"
  type        = string
}

variable "dns_subdomain" {
  description = "Subdomain prefix"
  type        = string
}

variable "dns_full_domain" {
  description = "Full domain name (subdomain.domain)"
  type        = string
}

variable "dns_resource_tags_json" {
  description = "Tags for DNS resources"
  type        = map(string)
  default     = {}
}
