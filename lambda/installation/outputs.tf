# The installation's report, in the shape the runner stores (README).

locals {
  scope_type_id                     = coalesce(var.scope_type.id, try(nullplatform_scope_type.this[0].id, null))
  scope_configuration_specification = coalesce(var.scope_configuration.id, try(nullplatform_provider_specification.scope_configuration[0].id, null))
  channel_id                        = var.channel_id != null ? var.channel_id : try(tostring(nullplatform_notification_channel.worker[0].id), null)
  placeholder_publish_hint          = "publish it with scope/placeholder/publish (PLACEHOLDER_IMAGE_REPO=<repository url>)"
}

output "outputs" {
  description = "What the runtime and the next verbs read."
  value = {
    role_arn                          = local.role_arn
    state_bucket                      = local.state_bucket
    placeholder_image_uri             = local.placeholder_image_uri
    scope_type_id                     = local.scope_type_id
    scope_configuration_specification = local.scope_configuration_specification
    channel_id                        = local.channel_id
  }
}

output "resources" {
  description = "Every resource this installation touched, with who owns it: owned (created here, removed on uninstall), provided (a parameter), adopted (found and reused, never removed)."
  value = concat(
    [for key, role in aws_iam_role.lambda : { type = "aws_iam_role", id = role.arn, target = key, ownership = "owned" }],
    [for key, target in var.targets : { type = "aws_iam_role", id = target.role_arn, target = key, ownership = target.role_from_entry ? "adopted" : "provided" } if target.role_arn != null],
    [for key, bucket in aws_s3_bucket.state : { type = "aws_s3_bucket", id = bucket.bucket, target = key, ownership = "owned" }],
    [for key, target in var.targets : { type = "aws_s3_bucket", id = target.state_bucket, target = key, ownership = target.scope_configuration_id != null ? "adopted" : "provided" } if target.state_bucket != null],
    [for key, repo in aws_ecr_repository.placeholder : { type = "aws_ecr_repository", id = repo.repository_url, target = key, ownership = "owned" }],
    [for key, target in var.targets : { type = "aws_ecr_repository", id = target.placeholder_repository_url, target = key, ownership = "adopted" } if target.placeholder_repository_url != null],
    [for key, target in var.targets : { type = "placeholder_image", id = target.placeholder_image_uri, target = key, ownership = target.scope_configuration_id != null ? "adopted" : "provided" } if target.placeholder_image_uri != null],
    [for key, target in var.targets : { type = "alb_listener", id = target.alb_listener_arn, target = key, ownership = "provided" } if target.alb_listener_arn != null],
    [for key, provider in nullplatform_provider_config.iam : { type = "provider_config", id = provider.id, target = key, ownership = "owned" }],
    [for key, target in var.targets : { type = "provider_config", id = target.iam_provider_id, target = key, ownership = "adopted" } if target.iam_provider_id != null],
    [for key, entry in terraform_data.iam_role_entry : { type = "iam_role_entry", id = "${entry.triggers_replace.provider_id}/lambda", target = key, ownership = "owned" }],
    [for key, config in nullplatform_provider_config.scope_configuration : { type = "scope_configuration", id = config.id, target = key, ownership = "owned" }],
    [for key, target in var.targets : { type = "scope_configuration", id = target.scope_configuration_id, target = key, ownership = "adopted" } if target.scope_configuration_id != null],
    [for spec in nullplatform_provider_specification.scope_configuration : { type = "provider_specification", id = spec.id, ownership = "owned" }],
    var.scope_configuration.id != null ? [{ type = "provider_specification", id = var.scope_configuration.id, ownership = var.scope_configuration.provided ? "provided" : "adopted" }] : [],
    [for scope_type in nullplatform_scope_type.this : { type = "scope_type", id = tostring(scope_type.id), ownership = "owned" }],
    var.scope_type.id != null ? [{ type = "scope_type", id = var.scope_type.id, ownership = var.scope_type.provided ? "provided" : "adopted" }] : [],
    [{ type = "nrn_settings", id = "${var.installation.nrn}/global.${var.installation.package_slug}_*", ownership = "owned" }],
    [for channel in nullplatform_notification_channel.worker : { type = "notification_channel", id = tostring(channel.id), ownership = "owned" }],
    var.channel_id != null ? [{ type = "notification_channel", id = var.channel_id, ownership = "adopted" }] : [],
  )
}

output "missing" {
  description = "Requirements that could not be satisfied here, with what to do."
  value = concat(
    [for key, target in var.targets : { need = "placeholder_image", target = key, hint = local.placeholder_publish_hint } if local.placeholder_image_uri[key] == null],
    [for key, target in var.targets : { need = "scope_configuration", target = key, hint = "written once the placeholder image exists; run update" } if target.scope_configuration_id == null && local.placeholder_image_uri[key] == null],
    [for key, target in var.targets : { need = "alb_listener", target = key, hint = "optional: scopes get no HTTP endpoint through an ALB; pass alb_listener_arn or publish load_balancer.public.listener_arn in the networking provider" } if target.alb_listener_arn == null],
  )
}
