mock_provider "aws" {
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/test-tg/50dc6c495c0c9188"
    }
  }
}

variables {
  alb_listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
  alb_target_group_name     = "test-tg"
  alb_host_header           = "api.internal.example.com"
  alb_rule_priority         = 100
  alb_health_check_enabled  = true
  alb_health_check_path     = "/health"
  alb_resource_tags_json    = {}
}

run "creates_lambda_target_group" {
  command = plan

  assert {
    condition     = aws_lb_target_group.lambda.name == "test-tg"
    error_message = "Target group name should be test-tg"
  }

  assert {
    condition     = aws_lb_target_group.lambda.target_type == "lambda"
    error_message = "Target type should be lambda"
  }
}

run "attaches_lambda_to_target_group" {
  command = plan

  assert {
    condition     = aws_lb_target_group_attachment.lambda.target_id == "arn:aws:lambda:us-east-1:123456789012:function:test-function:main"
    error_message = "Target should be the Lambda alias ARN"
  }
}

run "creates_listener_rule" {
  command = plan

  assert {
    condition     = aws_lb_listener_rule.lambda.priority == 100
    error_message = "Rule priority should be 100"
  }

  assert {
    condition     = aws_lb_listener_rule.lambda.listener_arn == "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/my-alb/50dc6c495c0c9188/f2f7dc8efc522ab2"
    error_message = "Listener ARN should match"
  }
}

run "configures_host_header_condition" {
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.lambda.condition) >= 1
    error_message = "Should have at least one condition"
  }
}

run "creates_lambda_permission_for_alb" {
  command = plan

  assert {
    condition     = aws_lambda_permission.alb.action == "lambda:InvokeFunction"
    error_message = "Permission should allow InvokeFunction"
  }

  assert {
    condition     = aws_lambda_permission.alb.principal == "elasticloadbalancing.amazonaws.com"
    error_message = "Principal should be elasticloadbalancing.amazonaws.com"
  }

  assert {
    condition     = aws_lambda_permission.alb.function_name == "test-function"
    error_message = "Function name should come from cross-module local"
  }

  assert {
    condition     = aws_lambda_permission.alb.qualifier == "main"
    error_message = "Qualifier should be the main alias name"
  }
}

run "configures_health_check" {
  command = plan

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].path == "/health"
    error_message = "Health check path should be /health"
  }

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].enabled == true
    error_message = "Health check should be enabled"
  }

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].interval == 35
    error_message = "Health check interval should be 35"
  }

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].timeout == 30
    error_message = "Health check timeout should be 30"
  }

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].healthy_threshold == 2
    error_message = "Healthy threshold should be 2"
  }

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].unhealthy_threshold == 2
    error_message = "Unhealthy threshold should be 2"
  }

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].matcher == "200-299"
    error_message = "Health check matcher should be 200-299"
  }
}

run "skips_health_check_when_disabled" {
  variables {
    alb_health_check_enabled = false
  }
  command = plan

  assert {
    condition     = length(aws_lb_target_group.lambda.health_check) == 0
    error_message = "Health check block should not be present when disabled"
  }
}

run "uses_custom_priority" {
  variables {
    alb_rule_priority = 50
  }
  command = plan

  assert {
    condition     = aws_lb_listener_rule.lambda.priority == 50
    error_message = "Rule priority should be 50"
  }
}

run "applies_tags_to_target_group" {
  variables {
    alb_resource_tags_json = {
      Environment = "test"
      Project     = "lambda-scope"
    }
  }
  command = plan

  assert {
    condition     = aws_lb_target_group.lambda.tags["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = aws_lb_target_group.lambda.tags["Project"] == "lambda-scope"
    error_message = "Project tag should be 'lambda-scope'"
  }

  assert {
    condition     = aws_lb_target_group.lambda.tags["ManagedBy"] == "custom-scope-role"
    error_message = "ManagedBy tag should be 'custom-scope-role'"
  }
}

run "configures_custom_health_check_path" {
  variables {
    alb_health_check_path = "/healthz"
  }
  command = plan

  assert {
    condition     = aws_lb_target_group.lambda.health_check[0].path == "/healthz"
    error_message = "Health check path should be /healthz"
  }
}

run "uses_different_host_header" {
  variables {
    alb_host_header = "api.example.com"
  }
  command = plan

  assert {
    condition     = length(aws_lb_listener_rule.lambda.condition) >= 1
    error_message = "Should have at least one condition for host header"
  }
}

run "creates_unique_target_group_name" {
  variables {
    alb_target_group_name = "my-app-prod-api"
  }
  command = plan

  assert {
    condition     = aws_lb_target_group.lambda.name == "my-app-prod-api"
    error_message = "Target group should use custom name"
  }
}

run "uses_qualified_lambda_arn_from_locals" {
  variables {
    test_lambda_alias_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-function:production"
  }
  command = plan

  assert {
    condition     = aws_lb_target_group_attachment.lambda.target_id == "arn:aws:lambda:us-east-1:123456789012:function:test-function:production"
    error_message = "Should use qualified Lambda ARN from cross-module local"
  }
}
