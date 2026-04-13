variable "api_gateway_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "api_gateway_stage_name" {
  description = "Name of the API stage"
  type        = string
  default     = "main"
}

variable "api_gateway_throttling_burst_limit" {
  description = "Throttling burst limit"
  type        = number
  default     = 5000
}

variable "api_gateway_throttling_rate_limit" {
  description = "Throttling rate limit"
  type        = number
  default     = 10000
}

variable "api_gateway_custom_domain" {
  description = "Custom domain name for the API (empty to skip)"
  type        = string
  default     = ""
}

variable "api_gateway_certificate_arn" {
  description = "ARN of the ACM certificate for custom domain"
  type        = string
  default     = ""
}

variable "api_gateway_resource_tags_json" {
  description = "Tags to apply to API Gateway resources"
  type        = map(string)
  default     = {}
}
