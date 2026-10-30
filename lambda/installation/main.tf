################################################################################
# scopes-lambda — installation (nullplatform layer)
#
# Installs the published scopes-lambda package in an organization. Reference it
# at a release tag:
#
#   source = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=vX.Y.Z"
#
# The tag fixes the installed version (local.release in versions.tf). Upgrading
# = moving the ref.
#
# The package brings the scope specification and its action specifications,
# read-only. This module creates, through tofu-modules'
# scope_package_installation and from this tag's templates, what each
# organization owns on top of it: the installation of the package at var.nrn,
# the scope type, the NRN settings that pick the scope's metrics and logs
# providers, and the scope-configuration provider specification.
#
# Only the nullplatform side, so it goes in the layer of your stack that
# registers specifications. Everything else stays where it is today:
#   - AWS (permissions role, placeholder repository, ALB): ../specs/requirements,
#     in your infrastructure layer;
#   - the agent channel, the IAM provider entry (selector "lambda") and the
#     scope's settings: your bindings layer.
# The outputs carry the names scope_definition outputs, so a stack that
# registered this scope with it switches by changing the module.
#
# Requires `np`, `gomplate` and `jq` on the machine running the apply (the NRN
# patch and the template rendering use them).
################################################################################

locals {
  package_slug = "nullplatform-aws-lambda"
  version      = trimprefix(local.release, "v")
}

module "package" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_package_installation?ref=feat/package-installation-layered"

  nrn             = var.nrn
  package_slug    = local.package_slug
  package_version = local.version
  visible_to      = var.visible_to

  local_specs_path     = abspath("${path.module}/..")
  create_agent_channel = false

  np_api_key                = var.np_api_key
  external_metrics_provider = var.external_metrics_provider
  external_logging_provider = var.external_logging_provider

  scope_type_name            = var.scope_type_name
  create_scope_configuration = var.create_scope_configuration
  scope_configuration_name   = var.scope_configuration_name
}
