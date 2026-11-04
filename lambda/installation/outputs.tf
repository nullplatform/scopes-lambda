output "scope_type_id" {
  description = "The scope type developers pick, created here or given."
  value       = local.scope_type_id
}

output "scope_configuration_specification_id" {
  description = "The scope-configuration schema, created here or given. target/ writes each environment's values under it."
  value       = local.scope_configuration_specification_id
}

output "scope_configuration_slug" {
  description = "Slug of that schema, what a provider config of it is typed with. Null when the schema was given: pass scope_configuration_slug to target/ yourself."
  value       = try(nullplatform_provider_specification.scope_configuration[0].slug, null)
}

output "channel_id" {
  description = "The agent channel, created here or given; null when the organization creates it elsewhere."
  value       = var.channel_id != null ? var.channel_id : try(tostring(nullplatform_notification_channel.worker[0].id), null)
}

output "resources" {
  description = "What this module touched, with who owns it: owned (created here, removed on destroy), provided (given by the caller, never removed)."
  value = concat(
    [for scope_type in nullplatform_scope_type.this : { type = "scope_type", id = tostring(scope_type.id), ownership = "owned" }],
    var.scope_type_id != null ? [{ type = "scope_type", id = var.scope_type_id, ownership = "provided" }] : [],
    [for spec in nullplatform_provider_specification.scope_configuration : { type = "provider_specification", id = spec.id, ownership = "owned" }],
    var.scope_configuration_specification_id != null ? [{ type = "provider_specification", id = var.scope_configuration_specification_id, ownership = "provided" }] : [],
    [{ type = "nrn_settings", id = "${var.installation.nrn}/global.${var.installation.package_slug}_*", ownership = "owned" }],
    [for channel in nullplatform_notification_channel.worker : { type = "notification_channel", id = tostring(channel.id), ownership = "owned" }],
    var.channel_id != null ? [{ type = "notification_channel", id = var.channel_id, ownership = "provided" }] : [],
  )
}
