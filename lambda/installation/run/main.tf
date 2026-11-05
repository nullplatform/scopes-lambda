################################################################################
# aws-lambda scope — installation, the runner root
#
# For installing without a Terraform repository of one's own: what a person
# or `np package install` runs. It configures the providers from the
# environment and calls the three modules: installation once, account once
# (one AWS provider, so one account) and environment once per dimension set
# the account serves. An organization with its own Terraform calls ../,
# ../account and ../environment directly, with its provider aliases, and does
# not need this.
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
# cluster. The region is the account's.
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

# Once: the runner's AWS provider is one account. Everything an environment
# needs from the cloud comes out of here, so two environments in this account
# never create a second role, bucket or repository.
module "account" {
  source = "../account"

  installation               = var.installation
  name                       = var.account.name
  agent_role_arn             = var.agent.role_arn
  role_arn                   = var.account.role_arn
  state_bucket               = var.account.state_bucket
  placeholder_image_uri      = var.account.placeholder_image_uri
  placeholder_repository_url = var.account.placeholder_repository_url
  alb_listener_arn           = var.account.alb_listener_arn
  assets_bucket_name         = var.assets_bucket_name
}

module "environment" {
  source   = "../environment"
  for_each = var.environments

  installation             = var.installation
  name                     = each.key
  dimensions               = each.value.dimensions
  role_arn                 = module.account.role_arn
  role_from_entry          = each.value.role_from_entry
  state_bucket             = module.account.state_bucket
  state_bucket_region      = module.account.state_bucket_region
  placeholder_image_uri    = module.account.placeholder_image_uri
  scope_configuration_slug = coalesce(var.scope_configuration.slug, module.installation.scope_configuration_slug)
  iam_provider_id          = each.value.iam_provider_id
  scope_configuration_id   = each.value.scope_configuration_id
  service_specification_id = var.service_specification_id
  agent_tags               = coalesce(each.value.agent_tags, var.agent.tags)
  channel_id               = each.value.channel_id
  create_channel           = var.create_channel
}
