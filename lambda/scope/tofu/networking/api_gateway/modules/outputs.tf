output "api_gateway_id" {
  description = "ID of the API Gateway"
  value       = aws_apigatewayv2_api.main.id
}

output "api_gateway_endpoint" {
  description = "Endpoint URL of the API Gateway"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_apigatewayv2_api.main.execution_arn
}

output "api_gateway_stage_id" {
  description = "ID of the API Gateway stage"
  value       = aws_apigatewayv2_stage.main.id
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway stage"
  value       = aws_apigatewayv2_stage.main.invoke_url
}

output "api_gateway_custom_domain_name" {
  description = "Custom domain name (if configured)"
  value       = local.api_gateway_create_custom_domain ? aws_apigatewayv2_domain_name.custom[0].domain_name : null
}

output "api_gateway_target_domain" {
  description = "Target domain for DNS alias record"
  value       = local.api_gateway_target_domain
}

output "api_gateway_target_zone_id" {
  description = "Hosted zone ID for DNS alias record"
  value       = local.api_gateway_target_zone_id
}
