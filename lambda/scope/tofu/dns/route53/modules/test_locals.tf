# NOTE: Files matching test_*.tf are skipped by compose_modules
# These variables simulate cross-module locals for isolated testing

variable "test_api_gateway_target_domain" {
  description = "Test-only: Simulates API Gateway module output"
  default     = ""
}

variable "test_api_gateway_target_zone_id" {
  description = "Test-only: Simulates API Gateway module output"
  default     = ""
}

variable "test_alb_host_header" {
  description = "Test-only: Simulates ALB module output"
  default     = ""
}

locals {
  api_gateway_target_domain  = var.test_api_gateway_target_domain
  api_gateway_target_zone_id = var.test_api_gateway_target_zone_id
  alb_host_header            = var.test_alb_host_header
}
