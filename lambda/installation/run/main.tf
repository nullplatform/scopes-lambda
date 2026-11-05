################################################################################
# aws-lambda scope — installation, the runner root
#
# For installing without a Terraform repository of one's own: what a person
# or `np package install` runs. It configures the providers from the
# environment and calls the two modules; one AWS provider, so one account,
# with as many dimension sets (targets) as given. An organization with its
# own Terraform calls ../ and ../target directly, with its provider aliases,
# and does not need this.
################################################################################

terraform {
  required_version = ">= 1.6"

  # No backend: lib/context passes the state file in NP_INSTALL_STATE.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    nullplatform = {
      source  = "nullplatform/nullplatform"
      version = ">= 0.0.106"
    }
  }
}

# Credentials are the runner's: a profile locally, the agent's role in the
# cluster. The region is the target's.
provider "aws" {
  region = var.aws_region
}

# NULLPLATFORM_API_KEY from the environment.
provider "nullplatform" {}

module "installation" {
  source = "../"

  installation                         = var.installation
  service_specification_id             = var.service_specification_id
  scope_type_id                        = var.scope_type.id
  scope_type_name                      = var.scope_type.name
  scope_type_description               = var.scope_type.description
  scope_configuration_specification_id = var.scope_configuration.id
  metrics_provider                     = var.metrics_provider
  log_provider                         = var.log_provider
}

module "target" {
  source   = "../target"
  for_each = var.targets

  installation               = var.installation
  name                       = each.key
  dimensions                 = each.value.dimensions
  agent_role_arn             = var.agent.role_arn
  service_specification_id   = var.service_specification_id
  scope_configuration_slug   = coalesce(var.scope_configuration.slug, module.installation.scope_configuration_slug)
  role_arn                   = each.value.role_arn
  role_from_entry            = each.value.role_from_entry
  iam_provider_id            = each.value.iam_provider_id
  state_bucket               = each.value.state_bucket
  placeholder_image_uri      = each.value.placeholder_image_uri
  placeholder_repository_url = each.value.placeholder_repository_url
  alb_listener_arn           = each.value.alb_listener_arn
  scope_configuration_id     = each.value.scope_configuration_id
  assets_bucket_name         = var.assets_bucket_name
  agent_tags                 = coalesce(each.value.agent_tags, var.agent.tags)
  channel_id                 = each.value.channel_id
  create_channel             = var.create_channel
}
