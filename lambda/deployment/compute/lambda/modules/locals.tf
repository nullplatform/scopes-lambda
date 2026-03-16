locals {
  # Compute module identifier
  lambda_module_name = "compute/lambda"

  # Reserved concurrency: -1 means unreserved (no limit), otherwise use the value
  lambda_reserved_concurrent_executions = var.lambda_reserved_concurrency_type == "reserved" ? var.lambda_reserved_concurrency_value : -1

  # Whether to create provisioned concurrency config
  lambda_create_provisioned_concurrency = var.lambda_provisioned_concurrency_type == "provisioned" && var.lambda_provisioned_concurrency_value > 0

  # Whether this is a container image deployment
  lambda_is_image = var.lambda_package_type == "Image"

  # Whether to create warmup alias
  lambda_create_warmup_alias = var.lambda_warmup_alias_name != "" && var.lambda_warmup_alias_name != null

  # VPC configuration - only include if provided
  lambda_has_vpc_config = var.lambda_vpc_config != null

  # Log group name follows AWS Lambda convention
  lambda_log_group_name = "/aws/lambda/${var.lambda_function_name}"

  # Default tags for Lambda resources
  lambda_default_tags = merge(var.lambda_tags, {
    ManagedBy = "terraform"
    Module    = local.lambda_module_name
  })

  # Cross-module outputs (consumed by networking layers)
  lambda_function_arn        = aws_lambda_function.main.arn
  lambda_function_name       = aws_lambda_function.main.function_name
  lambda_function_invoke_arn = aws_lambda_function.main.invoke_arn
  lambda_alias_arn           = aws_lambda_alias.main.arn
  lambda_alias_invoke_arn    = aws_lambda_alias.main.invoke_arn
  lambda_qualified_arn       = aws_lambda_alias.main.arn
  lambda_current_version     = aws_lambda_function.main.version
  lambda_main_alias_name     = aws_lambda_alias.main.name
}
