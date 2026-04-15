locals {
  # Module identifier
  api_gateway_module_name = "networking/api_gateway"

  # Whether to create custom domain resources
  api_gateway_create_custom_domain = var.api_gateway_custom_domain != "" && var.api_gateway_custom_domain != null

  # Default tags
  api_gateway_default_tags = merge(var.api_gateway_resource_tags_json, {
    ManagedBy = "custom-scope-role"
    Module    = local.api_gateway_module_name
  })

  # Cross-module outputs (consumed by dns layer)
  api_gateway_endpoint     = aws_apigatewayv2_api.main.api_endpoint
  api_gateway_id           = aws_apigatewayv2_api.main.id
  api_gateway_execution_arn = aws_apigatewayv2_api.main.execution_arn

  # For DNS layer - the target depends on whether custom domain is configured
  api_gateway_target_domain = local.api_gateway_create_custom_domain ? aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].target_domain_name : ""
  api_gateway_target_zone_id = local.api_gateway_create_custom_domain ? aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].hosted_zone_id : ""
}
