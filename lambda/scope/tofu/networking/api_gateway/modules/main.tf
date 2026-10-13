# The function lives in the scope's main state; networking has its own, so it reads the alias.
data "aws_lambda_alias" "main" {
  function_name = var.api_gateway_lambda_function_name
  name          = var.api_gateway_lambda_alias_name
}

# HTTP API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = var.api_gateway_name
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
    max_age       = 86400
  }

  tags = local.api_gateway_default_tags
}

# API Stage with auto-deploy
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.api_gateway_stage_name
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_gateway_throttling_burst_limit
    throttling_rate_limit  = var.api_gateway_throttling_rate_limit
  }

  tags = local.api_gateway_default_tags
}

# Lambda integration
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = data.aws_lambda_alias.main.invoke_arn
  payload_format_version = "2.0"
}

# Default route - catch all requests
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.api_gateway_lambda_function_name
  qualifier     = var.api_gateway_lambda_alias_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Custom domain (optional)
resource "aws_apigatewayv2_domain_name" "custom" {
  count = local.api_gateway_create_custom_domain ? 1 : 0

  domain_name = var.api_gateway_custom_domain

  domain_name_configuration {
    certificate_arn = var.api_gateway_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = local.api_gateway_default_tags
}

# API mapping for custom domain
resource "aws_apigatewayv2_api_mapping" "custom" {
  count = local.api_gateway_create_custom_domain ? 1 : 0

  api_id      = aws_apigatewayv2_api.main.id
  domain_name = aws_apigatewayv2_domain_name.custom[0].domain_name
  stage       = aws_apigatewayv2_stage.main.id
}

# DNS alias for the custom domain
resource "aws_route53_record" "api_gateway" {
  count = local.api_gateway_create_custom_domain && var.api_gateway_hosted_zone_id != "" ? 1 : 0

  zone_id = var.api_gateway_hosted_zone_id
  name    = var.api_gateway_custom_domain
  type    = "A"

  alias {
    name                   = local.api_gateway_target_domain
    zone_id                = local.api_gateway_target_zone_id
    evaluate_target_health = false
  }
}
