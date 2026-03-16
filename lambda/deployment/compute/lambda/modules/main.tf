# Main Lambda Function
resource "aws_lambda_function" "main" {
  function_name = var.lambda_function_name
  description   = var.lambda_description
  role          = local.lambda_role_arn
  package_type  = var.lambda_package_type

  # Deployment package from S3 (Zip only)
  s3_bucket = local.lambda_is_image ? null : var.lambda_s3_bucket
  s3_key    = local.lambda_is_image ? null : var.lambda_s3_key

  # Container image URI (Image only)
  image_uri = local.lambda_is_image ? var.lambda_image_uri : null

  # Runtime configuration (Zip only - Image infers from container)
  runtime       = local.lambda_is_image ? null : var.lambda_runtime
  handler       = local.lambda_is_image ? null : var.lambda_handler
  architectures = [var.lambda_architecture]

  # Resource allocation
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  # Ephemeral storage
  ephemeral_storage {
    size = var.lambda_ephemeral_storage
  }

  # Environment variables
  dynamic "environment" {
    for_each = length(var.lambda_environment_variables) > 0 ? [1] : []
    content {
      variables = var.lambda_environment_variables
    }
  }

  # Lambda layers
  layers = var.lambda_layers

  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = local.lambda_has_vpc_config ? [1] : []
    content {
      subnet_ids         = var.lambda_vpc_config.subnet_ids
      security_group_ids = var.lambda_vpc_config.security_group_ids
    }
  }

  # Reserved concurrency (-1 means unreserved)
  reserved_concurrent_executions = local.lambda_reserved_concurrent_executions

  # Publish a new version on each deployment
  publish = var.lambda_publish

  tags = local.lambda_default_tags

  # Cross-module dependency: wait for IAM propagation when the role was just created.
  # time_sleep.iam_propagation is defined in the iam module, which is always composed
  # alongside this module. When count = 0 (role pre-existed), this is a no-op.
  depends_on = [time_sleep.iam_propagation]

  lifecycle {
    # Ignore changes to code - managed via deployments
    ignore_changes = [
      # S3 key changes are handled by deployment workflow
    ]
  }
}

# Main alias for traffic routing
resource "aws_lambda_alias" "main" {
  name             = var.lambda_main_alias_name
  function_name    = aws_lambda_function.main.function_name
  function_version = aws_lambda_function.main.version

  lifecycle {
    # Routing config is managed by traffic switching scripts
    ignore_changes = [
      routing_config,
      function_version
    ]
  }
}

# Warmup alias (optional) - for pre-warming new versions before traffic shift
resource "aws_lambda_alias" "warmup" {
  count = local.lambda_create_warmup_alias ? 1 : 0

  name             = var.lambda_warmup_alias_name
  function_name    = aws_lambda_function.main.function_name
  function_version = aws_lambda_function.main.version

  lifecycle {
    # Version is managed by deployment workflow
    ignore_changes = [
      function_version
    ]
  }
}

# Provisioned concurrency configuration (optional)
resource "aws_lambda_provisioned_concurrency_config" "main" {
  count = local.lambda_create_provisioned_concurrency ? 1 : 0

  function_name                     = aws_lambda_function.main.function_name
  qualifier                         = aws_lambda_alias.main.name
  provisioned_concurrent_executions = var.lambda_provisioned_concurrency_value

  lifecycle {
    # Allow updates without recreation
    create_before_destroy = true
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.lambda_log_group_name
  retention_in_days = var.lambda_log_retention_days

  tags = local.lambda_default_tags
}
