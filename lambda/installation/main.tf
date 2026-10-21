################################################################################
# scopes-lambda — installation into an organization
#
# Everything an organization needs to use the published scopes-lambda package,
# kept next to the scope so whoever maintains the scope also maintains how it
# is installed. Reference it at a release tag:
#
#   source = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=vX.Y.Z"
#
# The tag fixes the installed version (local.release in versions.tf). Upgrading
# = moving the ref.
#
# The package brings the scope specification and its action specifications,
# read-only. A scope also needs pieces that belong to each organization, and
# this module creates them from the same tag's templates:
#   1. the AWS permissions role, placeholder ECR repository and optional ALB;
#   2. the installation of the package at var.nrn;
#   3. the scope type pointing at the package's specification;
#   4. the NRN settings that pick the scope's metrics and logs providers;
#   5. the scope-configuration provider specification (its schema);
#   6. the agent notification channel routing the scope's actions to the
#      package worker.
#
# Requires `np`, `gomplate` and `jq` on the machine running the apply (the NRN
# patch and the channel template rendering use them).
################################################################################

locals {
  package_slug = "scopes-lambda"
  version      = trimprefix(local.release, "v")
  service_path = "lambda"
  specs_path   = "${path.module}/../specs"

  # The specification the scope type points at: the package's, which this
  # organization does not own and only reaches through its bill of materials.
  specification_id = one([
    for component in data.nullplatform_package.this.components : component.resource_id
    if component.resource_type == "service_specification"
  ])
  specification_slug = data.nullplatform_service_specification.this.slug

  # The templates are gomplate; the two placeholders the per-organization
  # pieces use are substituted here instead of rendering them.
  scope_type_template = jsondecode(replace(replace(
    file("${local.specs_path}/scope-type-definition.json.tpl"),
    "{{ env.Getenv \"NRN\" }}", var.nrn),
    "{{ env.Getenv \"SERVICE_SPECIFICATION_ID\" }}", local.specification_id,
  ))
  scope_configuration_template = jsondecode(replace(
    file("${local.specs_path}/scope-configuration.json.tpl"),
    "{{ env.Getenv \"NRN\" }}", var.nrn,
  ))
}

# 1. AWS (same module the scope has always documented)
module "requirements" {
  source = "../specs/requirements"

  cluster_name                = var.cluster_name
  agent_role_arn              = var.agent_role_arn
  additional_agent_role_arns  = var.additional_agent_role_arns
  iam_create_role             = var.iam_create_role
  role_name                   = var.iam_role_name
  policies_name_prefix        = var.iam_policies_name_prefix
  iam_resource_tags_json      = var.iam_resource_tags
  placeholder_repository_name = var.placeholder_repository_name
  assets_bucket_name          = var.assets_bucket_name
  install_alb                 = var.install_alb
  vpc_id                      = var.vpc_id
  public_subnet_ids           = var.public_subnet_ids
  public_zone_id              = var.public_zone_id
  domain_name                 = var.domain_name
  certificate_arn             = var.certificate_arn
  alb_name                    = var.alb_name
}

# 2. The package, found by where it is visible (it is owned by the publisher
#    organization, not yours), installed at the version of this module's tag.
data "nullplatform_package" "this" {
  visible_at = var.nrn
  slug       = local.package_slug
  version    = local.version
}

resource "nullplatform_package_installation" "this" {
  nrn                 = var.nrn
  package_id          = data.nullplatform_package.this.id
  default_revision_id = data.nullplatform_package.this.revision_id
  visible_to          = var.visible_to
}

# The specification is readable here only once the installation covers nrn.
data "nullplatform_service_specification" "this" {
  id = local.specification_id

  depends_on = [nullplatform_package_installation.this]
}

# 3. Scope type
resource "nullplatform_scope_type" "this" {
  nrn           = var.nrn
  name          = local.scope_type_template.name
  description   = local.scope_type_template.description
  provider_type = local.scope_type_template.provider_type
  provider_id   = local.specification_id

  depends_on = [nullplatform_package_installation.this]
}

# 4. NRN settings: which providers serve this scope's metrics and logs.
#    No provider resource writes NRN settings, so this is the same `np nrn
#    patch` the scope_definition module runs.
resource "terraform_data" "nrn_settings" {
  triggers_replace = {
    nrn              = var.nrn
    slug             = local.specification_slug
    metrics_provider = var.external_metrics_provider
    logging_provider = var.external_logging_provider
  }

  provisioner "local-exec" {
    command = <<-EOT
      np nrn patch --nrn "${var.nrn}" --body '{
        "global.${local.specification_slug}_metric_provider": "${var.external_metrics_provider}",
        "global.${local.specification_slug}_log_provider": "${var.external_logging_provider}"
      }'
    EOT

    environment = var.np_api_key == null ? {} : { NP_API_KEY = var.np_api_key }
  }
}

# 5. Scope-configuration schema. Provider specifications are not part of a
#    package yet, so each organization gets its own, from this tag's template.
resource "nullplatform_provider_specification" "scope_configuration" {
  name             = coalesce(var.scope_configuration_name, local.scope_configuration_template.name)
  icon             = local.scope_configuration_template.icon
  description      = local.scope_configuration_template.description
  category         = local.scope_configuration_template.category
  allow_dimensions = local.scope_configuration_template.allow_dimensions
  visible_to       = [var.nrn]
  schema           = jsonencode(local.scope_configuration_template.schema)
}

# 6. Agent channel: package-exec to the package worker. The image lays the
#    repository down at /app/pkg (see the Dockerfile).
module "agent_channel" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v9.4.0"

  nrn         = var.nrn
  description = "scopes-lambda package worker"

  scope_specification_id   = local.specification_id
  scope_specification_slug = local.specification_slug

  service_path                           = local.service_path
  repository_notification_channel        = "https://raw.githubusercontent.com/nullplatform/scopes-lambda/refs/tags"
  repository_notification_channel_branch = local.release

  worker_orchestrator = true
  package_slug        = local.package_slug
  entrypoint          = "/app/pkg/${local.service_path}/entrypoint"

  tags_selectors = var.agent_tags_selectors

  depends_on = [nullplatform_scope_type.this]
}
