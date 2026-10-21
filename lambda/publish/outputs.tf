output "service_specification_id" {
  description = "Id of the published scope specification."
  value       = module.scope_definition.service_specification_id
}

output "package_id" {
  description = "Id of the published package."
  value       = module.scope_definition.package_id
}

output "package_version" {
  description = "Version published by this apply."
  value       = local.version
}

output "package_published_revision_id" {
  description = "Revision published by this apply."
  value       = module.scope_definition.package_published_revision_id
}
