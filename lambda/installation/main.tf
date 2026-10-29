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
# read-only. This module creates what each organization owns on top of it:
#   1. the AWS permissions role, placeholder ECR repository and optional ALB;
#   2. through tofu-modules' scope_package_installation, from this tag's
#      templates: the installation of the package at var.nrn, the scope type,
#      the NRN settings that pick the scope's metrics and logs providers, the
#      scope-configuration provider specification and the agent channel.
#
# Requires `np`, `gomplate` and `jq` on the machine running the apply (the NRN
# patch and the template rendering use them).
################################################################################

locals {
  package_slug = "nullplatform-aws-lambda"
  version      = trimprefix(local.release, "v")
  service_path = "lambda"
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

# 2. The package, installed at the version of this module's tag, and the
#    pieces this organization owns, from this tag's templates.
module "package" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_package_installation?ref=v9.7.0"

  nrn                  = var.nrn
  package_slug         = local.package_slug
  package_version      = local.version
  visible_to           = var.visible_to
  agent_tags_selectors = var.agent_tags_selectors

  local_specs_path = abspath("${path.module}/..")
  service_path     = local.service_path

  np_api_key                = var.np_api_key
  external_metrics_provider = var.external_metrics_provider
  external_logging_provider = var.external_logging_provider

  scope_type_name            = var.scope_type_name
  create_scope_configuration = var.create_scope_configuration
  scope_configuration_name   = var.scope_configuration_name
}
