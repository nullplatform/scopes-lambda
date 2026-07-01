locals {
  # Module identifier
  iam_module_name = "requirements-lambda"

  # Whether resources are created
  iam_create = var.iam_create_role

  # Derived names (overridable via variables). Defaults reproduce the names the
  # resources had when they lived inline in infrastructure/aws, so consuming
  # stacks can `moved` into this module without recreating anything.
  role_name            = var.role_name != "" ? var.role_name : "nullplatform_${var.cluster_name}_lambda_role"
  policies_name_prefix = var.policies_name_prefix != "" ? var.policies_name_prefix : "nullplatform_${var.cluster_name}"

  # Primary agent role trusted by the permissions role. Defaults to the
  # conventional agent role name for the cluster when not provided explicitly.
  agent_role_arn = var.agent_role_arn != "" ? var.agent_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nullplatform-${var.cluster_name}-agent-role"

  # Default tags applied to every IAM resource
  iam_default_tags = merge(var.iam_resource_tags_json, {
    ManagedBy = "nullplatform-custom-scope-role"
    Module    = local.iam_module_name
  })
}
