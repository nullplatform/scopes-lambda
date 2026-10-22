output "permissions_role_arn" {
  description = "ARN of the IAM role the scope assumes. Add it to your AWS IAM provider with selector \"lambda\"."
  value       = module.requirements.permissions_role_arn
}

output "placeholder_image_repository_url" {
  description = "Private ECR repository for the Lambda placeholder image (Image scopes). Publish the placeholder there and set PLACEHOLDER_IMAGE_URI_DEFAULT or deployment.placeholder_image_uri."
  value       = module.requirements.placeholder_image_repository_url
}

output "lambda_alb_listener_arn" {
  description = "HTTPS listener of the Lambda ALB, for the aws-networking-configuration provider. Empty when install_alb = false."
  value       = module.requirements.lambda_alb_listener_arn
}

output "installation_id" {
  description = "Id of the package installation."
  value       = nullplatform_package_installation.this.id
}

output "installed_version" {
  description = "Version new scopes are born with."
  value       = nullplatform_package_installation.this.default_version
}

output "missing_optional_requirements" {
  description = "Optional providers the package can use that are not configured at nrn or above it."
  value       = nullplatform_package_installation.this.missing_optional_requirements
}

output "scope_type_id" {
  description = "Id of the scope type created in your organization."
  value       = nullplatform_scope_type.this.id
}

output "scope_configuration_specification_id" {
  description = "Id of the scope-configuration provider specification. Configure a provider of it with the scope's OpenTofu state bucket and placeholder image."
  value       = nullplatform_provider_specification.scope_configuration.id
}

output "scope_configuration_specification_slug" {
  description = "Slug of the scope-configuration provider specification: the `type` of the provider config that holds the scope's settings."
  value       = nullplatform_provider_specification.scope_configuration.slug
}

output "notification_channel_id" {
  description = "Id of the agent notification channel."
  value       = module.agent_channel.notification_channel_id
}
