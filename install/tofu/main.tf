################################################################################
# Scope Definition
# Registers the service specification, scope type, and action specs in nullplatform.
################################################################################

module "scope_definition" {
  source = "../../../tofu-modules/nullplatform/scope_definition"

  nrn        = var.nrn
  np_api_key = var.np_api_key

  # Spec templates are fetched from install/specs/ in this repository
  service_path = "install"

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
}

################################################################################
# Scope Definition Agent Association
# Creates the notification channel that connects nullplatform events to the agent.
################################################################################

module "scope_definition_agent_association" {
  source = "../../../tofu-modules/nullplatform/scope_definition_agent_association"

  nrn     = var.nrn
  api_key = var.np_api_key

  scope_specification_id   = module.scope_definition.service_specification_id
  scope_specification_slug = module.scope_definition.service_slug

  # Notification channel template is also in install/specs/
  service_path = "install"

  repository_notification_channel        = var.github_raw_url
  repository_notification_channel_branch = var.github_branch

  repo_path = var.repo_path

  tags_selectors = var.tags_selectors
}
