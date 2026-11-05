output "role_arn" {
  description = "The role the worker assumes in this account, created here or given."
  value       = local.role_arn
}

output "state_bucket" {
  description = "The scopes' OpenTofu state bucket, created here or given."
  value       = local.state_bucket
}

output "placeholder_image_uri" {
  description = "The placeholder image, given or null while it is still to be published."
  value       = var.placeholder_image_uri
}

output "placeholder_repository_url" {
  description = "The placeholder repository, created here or given."
  value       = coalesce(var.placeholder_repository_url, try(aws_ecr_repository.placeholder[0].repository_url, null), try(split(":", var.placeholder_image_uri)[0], null))
}

output "channel_id" {
  description = "The agent channel for this target, created here or given; null when the organization creates it elsewhere."
  value       = var.channel_id != null ? var.channel_id : try(tostring(nullplatform_notification_channel.worker[0].id), null)
}

output "resources" {
  description = "What this module touched, with who owns it: owned (created here, removed on destroy), provided (given, never removed)."
  value = concat(
    [for channel in nullplatform_notification_channel.worker : { type = "notification_channel", id = tostring(channel.id), target = var.name, ownership = "owned" }],
    var.channel_id != null ? [{ type = "notification_channel", id = var.channel_id, target = var.name, ownership = "provided" }] : [],
    [for role in aws_iam_role.lambda : { type = "aws_iam_role", id = role.arn, target = var.name, ownership = "owned" }],
    var.role_arn != null ? [{ type = "aws_iam_role", id = var.role_arn, target = var.name, ownership = "provided" }] : [],
    [for bucket in aws_s3_bucket.state : { type = "aws_s3_bucket", id = bucket.bucket, target = var.name, ownership = "owned" }],
    var.state_bucket != null ? [{ type = "aws_s3_bucket", id = var.state_bucket, target = var.name, ownership = "provided" }] : [],
    [for repo in aws_ecr_repository.placeholder : { type = "aws_ecr_repository", id = repo.repository_url, target = var.name, ownership = "owned" }],
    var.placeholder_repository_url != null ? [{ type = "aws_ecr_repository", id = var.placeholder_repository_url, target = var.name, ownership = "provided" }] : [],
    var.placeholder_image_uri != null ? [{ type = "placeholder_image", id = var.placeholder_image_uri, target = var.name, ownership = "provided" }] : [],
    var.alb_listener_arn != null ? [{ type = "alb_listener", id = var.alb_listener_arn, target = var.name, ownership = "provided" }] : [],
    [for provider in nullplatform_provider_config.iam : { type = "provider_config", id = provider.id, target = var.name, ownership = "owned" }],
    var.iam_provider_id != null ? [{ type = "provider_config", id = var.iam_provider_id, target = var.name, ownership = "provided" }] : [],
    [for entry in terraform_data.iam_role_entry : { type = "iam_role_entry", id = "${entry.triggers_replace.provider_id}/lambda", target = var.name, ownership = "owned" }],
    [for config in nullplatform_provider_config.scope_configuration : { type = "scope_configuration", id = config.id, target = var.name, ownership = "owned" }],
    var.scope_configuration_id != null ? [{ type = "scope_configuration", id = var.scope_configuration_id, target = var.name, ownership = "provided" }] : [],
  )
}

output "missing" {
  description = "Requirements that could not be satisfied here, with what to do."
  value = concat(
    var.placeholder_image_uri == null ? [{ need = "placeholder_image", target = var.name, hint = "publish it with scope/placeholder/publish (PLACEHOLDER_IMAGE_REPO=<repository url>), then pass placeholder_image_uri" }] : [],
    var.scope_configuration_id == null && var.placeholder_image_uri == null ? [{ need = "scope_configuration", target = var.name, hint = "written once the placeholder image is known" }] : [],
    var.alb_listener_arn == null ? [{ need = "alb_listener", target = var.name, hint = "optional: scopes get no HTTP endpoint through an ALB; pass alb_listener_arn" }] : [],
  )
}
