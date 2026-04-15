mock_provider "aws" {}

variables {
  lambda_function_name       = "test-function"
  lambda_runtime             = "nodejs20.x"
  lambda_handler             = "index.handler"
  lambda_memory_size         = 256
  lambda_timeout             = 30
  lambda_ephemeral_storage   = 512
  lambda_architecture        = "arm64"
  lambda_role_arn            = "arn:aws:iam::123456789012:role/test-role"
  lambda_s3_bucket           = "test-bucket"
  lambda_s3_key              = "code.zip"
  lambda_environment_variables = {
    NODE_ENV = "production"
  }
  lambda_layers                        = []
  lambda_vpc_config                    = null
  lambda_reserved_concurrency_type     = "unreserved"
  lambda_reserved_concurrency_value    = 0
  lambda_provisioned_concurrency_type  = "unprovisioned"
  lambda_provisioned_concurrency_value = 0
  lambda_main_alias_name               = "main"
  lambda_warmup_alias_name             = ""
  lambda_log_retention_days            = 30
  lambda_tags                          = {}
}

run "creates_lambda_function" {
  command = plan

  assert {
    condition     = aws_lambda_function.main.function_name == "test-function"
    error_message = "Function name should be test-function"
  }

  assert {
    condition     = aws_lambda_function.main.runtime == "nodejs20.x"
    error_message = "Runtime should be nodejs20.x"
  }

  assert {
    condition     = aws_lambda_function.main.handler == "index.handler"
    error_message = "Handler should be index.handler"
  }

  assert {
    condition     = aws_lambda_function.main.memory_size == 256
    error_message = "Memory size should be 256"
  }

  assert {
    condition     = aws_lambda_function.main.timeout == 30
    error_message = "Timeout should be 30"
  }

  assert {
    condition     = contains(aws_lambda_function.main.architectures, "arm64")
    error_message = "Architecture should be arm64"
  }
}

run "creates_lambda_with_x86_architecture" {
  variables {
    lambda_architecture = "x86_64"
  }
  command = plan

  assert {
    condition     = contains(aws_lambda_function.main.architectures, "x86_64")
    error_message = "Architecture should be x86_64"
  }
}

run "creates_main_alias" {
  command = plan

  assert {
    condition     = aws_lambda_alias.main.name == "main"
    error_message = "Main alias should be named 'main'"
  }

  assert {
    condition     = aws_lambda_alias.main.function_name == "test-function"
    error_message = "Alias should point to the Lambda function"
  }
}

run "creates_cloudwatch_log_group" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.lambda.name == "/aws/lambda/test-function"
    error_message = "Log group should match function name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 30
    error_message = "Log retention should be 30 days"
  }
}

run "creates_warmup_alias_when_configured" {
  variables {
    lambda_warmup_alias_name = "warm"
  }
  command = plan

  assert {
    condition     = length(aws_lambda_alias.warmup) == 1
    error_message = "Warmup alias should be created when name is provided"
  }

  assert {
    condition     = aws_lambda_alias.warmup[0].name == "warm"
    error_message = "Warmup alias should be named 'warm'"
  }
}

run "skips_warmup_alias_when_not_configured" {
  variables {
    lambda_warmup_alias_name = ""
  }
  command = plan

  assert {
    condition     = length(aws_lambda_alias.warmup) == 0
    error_message = "Warmup alias should not be created when name is empty"
  }
}

run "configures_reserved_concurrency_when_reserved" {
  variables {
    lambda_reserved_concurrency_type  = "reserved"
    lambda_reserved_concurrency_value = 10
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.reserved_concurrent_executions == 10
    error_message = "Reserved concurrency should be 10"
  }
}

run "skips_reserved_concurrency_when_unreserved" {
  variables {
    lambda_reserved_concurrency_type  = "unreserved"
    lambda_reserved_concurrency_value = 0
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.reserved_concurrent_executions == null || aws_lambda_function.main.reserved_concurrent_executions == -1
    error_message = "Reserved concurrency should not be set"
  }
}

run "configures_provisioned_concurrency_when_enabled" {
  variables {
    lambda_provisioned_concurrency_type  = "provisioned"
    lambda_provisioned_concurrency_value = 5
  }
  command = plan

  assert {
    condition     = length(aws_lambda_provisioned_concurrency_config.main) == 1
    error_message = "Provisioned concurrency config should be created"
  }

  assert {
    condition     = aws_lambda_provisioned_concurrency_config.main[0].provisioned_concurrent_executions == 5
    error_message = "Provisioned concurrency should be 5"
  }
}

run "skips_provisioned_concurrency_when_not_enabled" {
  variables {
    lambda_provisioned_concurrency_type  = "unprovisioned"
    lambda_provisioned_concurrency_value = 0
  }
  command = plan

  assert {
    condition     = length(aws_lambda_provisioned_concurrency_config.main) == 0
    error_message = "Provisioned concurrency config should not be created"
  }
}

run "configures_vpc_when_provided" {
  variables {
    lambda_vpc_config = {
      subnet_ids         = ["subnet-11111111", "subnet-22222222"]
      security_group_ids = ["sg-12345678"]
    }
  }
  command = plan

  assert {
    condition     = length(aws_lambda_function.main.vpc_config) == 1
    error_message = "VPC config should be present"
  }

  assert {
    condition     = length(aws_lambda_function.main.vpc_config[0].subnet_ids) == 2
    error_message = "Should have 2 subnet IDs"
  }

  assert {
    condition     = length(aws_lambda_function.main.vpc_config[0].security_group_ids) == 1
    error_message = "Should have 1 security group"
  }
}

run "skips_vpc_config_when_not_provided" {
  variables {
    lambda_vpc_config = null
  }
  command = plan

  assert {
    condition     = length(aws_lambda_function.main.vpc_config) == 0
    error_message = "VPC config should not be present when no subnets provided"
  }
}

run "adds_layers_when_provided" {
  variables {
    lambda_layers = [
      "arn:aws:lambda:us-east-1:123456789012:layer:my-layer:1",
      "arn:aws:lambda:us-east-1:123456789012:layer:np-agent:5"
    ]
  }
  command = plan

  assert {
    condition     = length(aws_lambda_function.main.layers) == 2
    error_message = "Should have 2 layers"
  }
}

run "skips_layers_when_empty" {
  variables {
    lambda_layers = []
  }
  command = plan

  assert {
    condition     = length(aws_lambda_function.main.layers) == 0
    error_message = "Should have no layers"
  }
}

run "sets_environment_variables" {
  variables {
    lambda_environment_variables = {
      NODE_ENV = "production"
      API_URL  = "https://api.example.com"
    }
  }
  command = plan

  assert {
    condition     = length(aws_lambda_function.main.environment) == 1
    error_message = "Environment block should be present"
  }

  assert {
    condition     = aws_lambda_function.main.environment[0].variables["NODE_ENV"] == "production"
    error_message = "NODE_ENV should be production"
  }

  assert {
    condition     = aws_lambda_function.main.environment[0].variables["API_URL"] == "https://api.example.com"
    error_message = "API_URL should be set"
  }
}

run "skips_environment_when_empty" {
  variables {
    lambda_environment_variables = {}
  }
  command = plan

  assert {
    condition     = length(aws_lambda_function.main.environment) == 0
    error_message = "Environment block should not be present when empty"
  }
}

run "configures_ephemeral_storage" {
  variables {
    lambda_ephemeral_storage = 1024
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.ephemeral_storage[0].size == 1024
    error_message = "Ephemeral storage should be 1024 MB"
  }
}

run "uses_s3_deployment_package" {
  command = plan

  assert {
    condition     = aws_lambda_function.main.s3_bucket == "test-bucket"
    error_message = "S3 bucket should be test-bucket"
  }

  assert {
    condition     = aws_lambda_function.main.s3_key == "code.zip"
    error_message = "S3 key should be code.zip"
  }
}

run "applies_tags_to_resources" {
  variables {
    lambda_tags = {
      Environment = "test"
      Project     = "lambda-scope"
    }
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.tags["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = aws_lambda_function.main.tags["Project"] == "lambda-scope"
    error_message = "Project tag should be 'lambda-scope'"
  }
}

run "sets_custom_log_retention" {
  variables {
    lambda_log_retention_days = 90
  }
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 90
    error_message = "Log retention should be 90 days"
  }
}

run "creates_function_with_python_runtime" {
  variables {
    lambda_runtime = "python3.12"
    lambda_handler = "lambda_function.handler"
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.runtime == "python3.12"
    error_message = "Runtime should be python3.12"
  }

  assert {
    condition     = aws_lambda_function.main.handler == "lambda_function.handler"
    error_message = "Handler should be lambda_function.handler"
  }
}

run "creates_function_with_high_memory" {
  variables {
    lambda_memory_size = 3008
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.memory_size == 3008
    error_message = "Memory size should be 3008"
  }
}

run "creates_function_with_long_timeout" {
  variables {
    lambda_timeout = 900
  }
  command = plan

  assert {
    condition     = aws_lambda_function.main.timeout == 900
    error_message = "Timeout should be 900 (max)"
  }
}
