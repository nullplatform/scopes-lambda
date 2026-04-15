mock_provider "aws" {
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id             = "abc123def4"
      api_endpoint   = "https://abc123def4.execute-api.us-east-1.amazonaws.com"
      execution_arn  = "arn:aws:execute-api:us-east-1:123456789012:abc123def4"
    }
  }
  mock_resource "aws_apigatewayv2_domain_name" {
    defaults = {
      domain_name_configuration = {
        target_domain_name = "d-abc123.execute-api.us-east-1.amazonaws.com"
        hosted_zone_id     = "Z1UJRXOUMOOFQ8"
      }
    }
  }
}

variables {
  api_gateway_name                   = "test-api"
  api_gateway_stage_name             = "main"
  api_gateway_throttling_burst_limit = 5000
  api_gateway_throttling_rate_limit  = 10000
  api_gateway_custom_domain          = ""
  api_gateway_certificate_arn        = ""
  api_gateway_resource_tags_json     = {}
}

run "creates_http_api" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.main.name == "test-api"
    error_message = "API name should be test-api"
  }

  assert {
    condition     = aws_apigatewayv2_api.main.protocol_type == "HTTP"
    error_message = "Protocol should be HTTP"
  }
}

run "creates_stage_with_auto_deploy" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_stage.main.name == "main"
    error_message = "Stage name should be main"
  }

  assert {
    condition     = aws_apigatewayv2_stage.main.auto_deploy == true
    error_message = "Stage should auto deploy"
  }
}

run "creates_lambda_integration" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_integration.lambda.integration_type == "AWS_PROXY"
    error_message = "Integration type should be AWS_PROXY"
  }

  assert {
    condition     = aws_apigatewayv2_integration.lambda.integration_method == "POST"
    error_message = "Integration method should be POST"
  }

  assert {
    condition     = aws_apigatewayv2_integration.lambda.payload_format_version == "2.0"
    error_message = "Payload format should be 2.0"
  }
}

run "creates_default_route" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_route.default.route_key == "$default"
    error_message = "Route key should be $default"
  }
}

run "creates_lambda_permission" {
  command = plan

  assert {
    condition     = aws_lambda_permission.api_gateway.action == "lambda:InvokeFunction"
    error_message = "Permission should allow InvokeFunction"
  }

  assert {
    condition     = aws_lambda_permission.api_gateway.principal == "apigateway.amazonaws.com"
    error_message = "Principal should be apigateway.amazonaws.com"
  }

  assert {
    condition     = aws_lambda_permission.api_gateway.function_name == "test-function"
    error_message = "Function name should come from cross-module local"
  }

  assert {
    condition     = aws_lambda_permission.api_gateway.qualifier == "main"
    error_message = "Qualifier should be the main alias name"
  }
}

run "configures_cors" {
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_api.main.cors_configuration) == 1
    error_message = "CORS configuration should be present"
  }

  assert {
    condition     = contains(aws_apigatewayv2_api.main.cors_configuration[0].allow_origins, "*")
    error_message = "CORS should allow all origins"
  }

  assert {
    condition     = contains(aws_apigatewayv2_api.main.cors_configuration[0].allow_methods, "*")
    error_message = "CORS should allow all methods"
  }
}

run "creates_custom_domain_when_configured" {
  variables {
    api_gateway_custom_domain   = "api.example.com"
    api_gateway_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_domain_name.custom) == 1
    error_message = "Custom domain should be created"
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.custom[0].domain_name == "api.example.com"
    error_message = "Domain name should be api.example.com"
  }
}

run "skips_custom_domain_when_not_configured" {
  variables {
    api_gateway_custom_domain = ""
  }
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_domain_name.custom) == 0
    error_message = "Custom domain should not be created"
  }
}

run "creates_api_mapping_with_custom_domain" {
  variables {
    api_gateway_custom_domain   = "api.example.com"
    api_gateway_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_api_mapping.custom) == 1
    error_message = "API mapping should be created"
  }
}

run "skips_api_mapping_without_custom_domain" {
  variables {
    api_gateway_custom_domain = ""
  }
  command = plan

  assert {
    condition     = length(aws_apigatewayv2_api_mapping.custom) == 0
    error_message = "API mapping should not be created without custom domain"
  }
}

run "applies_tags_to_api" {
  variables {
    api_gateway_resource_tags_json = {
      Environment = "test"
      Project     = "lambda-scope"
    }
  }
  command = plan

  assert {
    condition     = aws_apigatewayv2_api.main.tags["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = aws_apigatewayv2_api.main.tags["Project"] == "lambda-scope"
    error_message = "Project tag should be 'lambda-scope'"
  }

  assert {
    condition     = aws_apigatewayv2_api.main.tags["ManagedBy"] == "custom-scope-role"
    error_message = "ManagedBy tag should be 'custom-scope-role'"
  }
}

run "uses_custom_stage_name" {
  variables {
    api_gateway_stage_name = "production"
  }
  command = plan

  assert {
    condition     = aws_apigatewayv2_stage.main.name == "production"
    error_message = "Stage name should be production"
  }
}

run "configures_throttling_defaults" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_stage.main.default_route_settings[0].throttling_burst_limit == 5000
    error_message = "Throttling burst limit should be 5000"
  }

  assert {
    condition     = aws_apigatewayv2_stage.main.default_route_settings[0].throttling_rate_limit == 10000
    error_message = "Throttling rate limit should be 10000"
  }
}

run "uses_custom_throttling_limits" {
  variables {
    api_gateway_throttling_burst_limit = 1000
    api_gateway_throttling_rate_limit  = 2000
  }
  command = plan

  assert {
    condition     = aws_apigatewayv2_stage.main.default_route_settings[0].throttling_burst_limit == 1000
    error_message = "Throttling burst limit should be 1000"
  }

  assert {
    condition     = aws_apigatewayv2_stage.main.default_route_settings[0].throttling_rate_limit == 2000
    error_message = "Throttling rate limit should be 2000"
  }
}
