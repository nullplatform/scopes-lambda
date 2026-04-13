# NOTE: Files matching test_*.tf are skipped by compose_modules
# These variables simulate cross-module locals for isolated testing

variable "test_lambda_alias_arn" {
  description = "Test-only: Simulates lambda module output"
  default     = "arn:aws:lambda:us-east-1:123456789012:function:test-function:main"
}

variable "test_lambda_function_name" {
  description = "Test-only: Simulates lambda module output"
  default     = "test-function"
}

variable "test_lambda_main_alias_name" {
  description = "Test-only: Simulates lambda module output"
  default     = "main"
}

locals {
  lambda_alias_arn       = var.test_lambda_alias_arn
  lambda_function_name   = var.test_lambda_function_name
  lambda_main_alias_name = var.test_lambda_main_alias_name
}
