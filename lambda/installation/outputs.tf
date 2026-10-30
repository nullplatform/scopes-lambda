output "installation_id" {
  description = "Id of the package installation."
  value       = module.package.installation_id
}

output "installed_version" {
  description = "Version new scopes are born with."
  value       = module.package.installed_version
}

output "missing_optional_requirements" {
  description = "Optional providers the package can use that are not configured at nrn or above it."
  value       = module.package.missing_optional_requirements
}

output "package_slug" {
  description = "Slug of the package: the package_slug of the agent channel."
  value       = local.package_slug
}

output "service_specification_id" {
  description = "Id of the scope specification: the scope_specification_id of the agent channel."
  value       = module.package.service_specification_id
}

output "service_specification_slug" {
  description = "Slug of the scope specification: what the agent channel filters on."
  value       = module.package.service_specification_slug
}

output "scope_type_id" {
  description = "Id of the scope type created in your organization."
  value       = module.package.scope_type_id
}

output "scope_configuration_specification_id" {
  description = "Id of the scope-configuration provider specification. Null with create_scope_configuration = false."
  value       = module.package.scope_configuration_specification_id
}

output "scope_configuration_specification_slug" {
  description = "Slug of the scope-configuration provider specification: the `type` of the provider config that holds the scope's settings. Null with create_scope_configuration = false."
  value       = module.package.scope_configuration_specification_slug
}

# Same names as scope_definition's outputs.

output "service_slug" {
  description = "Same as service_specification_slug."
  value       = module.package.service_slug
}

output "provider_specification_slug" {
  description = "Same as scope_configuration_specification_slug."
  value       = module.package.provider_specification_slug
}

output "package_id" {
  description = "Id of the installed package."
  value       = module.package.package_id
}

output "package_default_version" {
  description = "Same as installed_version."
  value       = module.package.package_default_version
}
