locals {
  # Module identifier
  iam_module_name = "iam"

  # Determine the role ARN to use
  lambda_role_arn = var.iam_create_role ? aws_iam_role.lambda[0].arn : var.lambda_role_arn

  # Default tags
  iam_default_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "terraform"
    Module    = local.iam_module_name
  })

  # VPC access policy ARN — kept as managed policy because EC2 network interface
  # operations cannot be scoped to specific resources (AWS limitation).
  lambda_vpc_access_policy = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"

  # Managed policies to attach (only VPC when enabled)
  iam_managed_policies = var.iam_vpc_enabled ? [local.lambda_vpc_access_policy] : []
}
