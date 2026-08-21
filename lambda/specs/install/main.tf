################################################################################
# Scope Definition
# Registers the service specification, scope type, and action specs in nullplatform.
################################################################################

module "scope_definition" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition?ref=main"

  nrn        = var.nrn
  np_api_key = var.np_api_key

  service_path = var.service_path

  repository_service_spec            = var.github_raw_url
  repository_service_spec_branch     = var.github_branch
  repository_scope_template          = var.github_raw_url
  repository_scope_template_branch   = var.github_branch
  repository_action_templates        = var.github_raw_url
  repository_action_templates_branch = var.github_branch

  repo_path = var.repo_path

  service_spec_name        = var.service_spec_name
  service_spec_description = var.service_spec_description

  action_spec_names = [
    "adjust-provisioned-concurrency",
    "adjust-reserved-concurrency",
    "create-scope",
    "delete-deployment",
    "delete-scope",
    "diagnose-deployment",
    "diagnose-scope",
    "finalize-blue-green",
    "invoke",
    "rollback-deployment",
    "start-blue-green",
    "start-initial",
    "switch-traffic",
    "update-scope",
  ]

  external_metrics_provider = var.external_metrics_provider
  external_logging_provider = var.external_logging_provider

  create_scope_configuration = true
}

################################################################################
# Scope Definition Agent Association
# Creates the notification channel that connects nullplatform events to the agent.
################################################################################

module "scope_definition_agent_association" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=main"

  nrn     = var.nrn
  api_key = var.np_api_key

  # description = "Notification channel for AWS Lambda scope definition"

  scope_specification_id   = module.scope_definition.service_specification_id
  scope_specification_slug = module.scope_definition.service_slug

  service_path = var.service_path

  repository_notification_channel        = var.github_raw_url
  repository_notification_channel_branch = var.github_branch

  repo_path = var.repo_path

  tags_selectors = var.tags_selectors

  enabled_override       = var.overrides_enabled
  override_repo_path     = var.overrides_repo_path
  overrides_service_path = var.overrides_service_path
}
