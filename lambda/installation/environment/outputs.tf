output "iam_provider_id" {
  description = "The IAM provider holding this environment's lambda entry, created here or given."
  value       = var.iam_provider_id != null ? var.iam_provider_id : try(nullplatform_provider_config.iam[0].id, null)
}

output "scope_configuration_id" {
  description = "The scope-configuration for these dimensions, written here or given; null while the placeholder image is unknown."
  value       = var.scope_configuration_id != null ? var.scope_configuration_id : try(nullplatform_provider_config.scope_configuration[0].id, null)
}

output "channel_id" {
  description = "The agent channel for this environment, created here or given; null when the organization creates it elsewhere."
  value       = var.channel_id != null ? var.channel_id : try(tostring(nullplatform_notification_channel.worker[0].id), null)
}

output "resources" {
  description = "What this module touched, with who owns it: owned (created here, removed on destroy), provided (given, never removed)."
  value = concat(
    [for provider in nullplatform_provider_config.iam : { type = "provider_config", id = provider.id, environment = var.name, ownership = "owned" }],
    var.iam_provider_id != null ? [{ type = "provider_config", id = var.iam_provider_id, environment = var.name, ownership = "provided" }] : [],
    [for entry in terraform_data.iam_role_entry : { type = "iam_role_entry", id = "${entry.triggers_replace.provider_id}/lambda", environment = var.name, ownership = "owned" }],
    [for config in nullplatform_provider_config.scope_configuration : { type = "scope_configuration", id = config.id, environment = var.name, ownership = "owned" }],
    var.scope_configuration_id != null ? [{ type = "scope_configuration", id = var.scope_configuration_id, environment = var.name, ownership = "provided" }] : [],
    [for channel in nullplatform_notification_channel.worker : { type = "notification_channel", id = tostring(channel.id), environment = var.name, ownership = "owned" }],
    var.channel_id != null ? [{ type = "notification_channel", id = var.channel_id, environment = var.name, ownership = "provided" }] : [],
  )
}

output "missing" {
  description = "Requirements that could not be satisfied here, with what to do."
  value = concat(
    var.scope_configuration_id == null && var.placeholder_image_uri == null ? [{ need = "scope_configuration", environment = var.name, hint = "written once the account's placeholder image is known" }] : [],
  )
}
