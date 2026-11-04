################################################################################
# aws-lambda scope — installation
#
# One root module for everything the scope needs in an organization, cloud and
# platform at once. Every requirement is a parameter or is provisioned here
# when the parameter is absent (variables.tf). Ownership rules:
#   - cloud and networking providers are read by lib/context, never written;
#   - what is created here is owned, and uninstall removes it;
#   - what is found is adopted: the copy's scope-configuration schema, an
#     existing scope type, an IAM provider (which only gets this package's
#     entry), a channel, an existing role under selector "lambda".
################################################################################

data "aws_caller_identity" "current" {}

locals {
  installation_suffix = substr(replace(var.installation.id, "-", ""), 0, 8)
  account_id          = data.aws_caller_identity.current.account_id

  targets_creating_role     = { for key, target in var.targets : key => target if target.role_arn == null }
  targets_creating_bucket   = { for key, target in var.targets : key => target if target.state_bucket == null }
  targets_creating_repo     = { for key, target in var.targets : key => target if target.placeholder_image_uri == null }
  targets_creating_provider = { for key, target in var.targets : key => target if target.iam_provider_id == null }
  # An entry is written only where the provider exists and the role did not
  # come from that very entry.
  targets_writing_entry = { for key, target in var.targets : key => target if target.iam_provider_id != null && !target.role_from_entry }

  role_arn     = { for key, target in var.targets : key => coalesce(target.role_arn, try(aws_iam_role.lambda[key].arn, null)) }
  state_bucket = { for key, target in var.targets : key => coalesce(target.state_bucket, try(aws_s3_bucket.state[key].bucket, null)) }
  # The image is never built here (it needs docker buildx); a target without
  # one gets the repository and a `missing` entry telling how to publish it.
  placeholder_image_uri = { for key, target in var.targets : key => target.placeholder_image_uri }

  # A scope-configuration can be written only once both values are known.
  targets_creating_configuration = {
    for key, target in var.targets : key => target
    if target.scope_configuration_id == null && local.placeholder_image_uri[key] != null
  }

  # The scope's own template, read as is: only the NRN placeholder is filled.
  scope_configuration_template = jsondecode(replace(
    file("${path.module}/${var.scope_configuration_template}"),
    "{{ env.Getenv \"NRN\" }}", var.installation.nrn,
  ))
}

# ── Cloud plane (what specs/requirements is today) ──

resource "aws_iam_role" "lambda" {
  for_each = local.targets_creating_role

  name        = "nullplatform-${var.installation.package_slug}-${local.installation_suffix}-${each.key}"
  description = "Permissions role assumed by the nullplatform agent for the ${var.installation.package_slug} package (installation ${var.installation.id}, target ${each.key})"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.agent.role_arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Target       = each.key
  }
}

resource "aws_iam_role_policy" "lambda" {
  for_each = aws_iam_role.lambda
  name     = "lambda"
  role     = each.value.name
  policy   = file("${path.module}/policies/lambda.json")
}

resource "aws_iam_role_policy" "lambda_iam" {
  for_each = aws_iam_role.lambda
  name     = "lambda-iam"
  role     = each.value.name
  policy   = file("${path.module}/policies/lambda-iam.json")
}

resource "aws_iam_role_policy" "lambda_networking" {
  for_each = aws_iam_role.lambda
  name     = "lambda-networking"
  role     = each.value.name
  policy   = file("${path.module}/policies/lambda-networking.json")
}

# The storage policy names the state bucket, so a provided one is covered too.
resource "aws_iam_role_policy" "lambda_storage" {
  for_each = aws_iam_role.lambda
  name     = "lambda-storage"
  role     = each.value.name
  policy = templatefile("${path.module}/policies/lambda-storage.json.tftpl", {
    state_bucket       = local.state_bucket[each.key]
    assets_bucket_name = var.assets_bucket_name
  })
}

# Per-scope OpenTofu state. Named under the prefix the storage policy covers.
resource "aws_s3_bucket" "state" {
  for_each = local.targets_creating_bucket

  bucket = "nullplatform-lambda-tfstate-${local.account_id}-${local.installation_suffix}-${each.key}"

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Target       = each.key
  }
}

resource "aws_s3_bucket_versioning" "state" {
  for_each = aws_s3_bucket.state
  bucket   = each.value.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "state" {
  for_each                = aws_s3_bucket.state
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The private repository Lambda pulls the placeholder from. The image itself is
# published by scope/placeholder/publish (docker buildx), reported as missing.
resource "aws_ecr_repository" "placeholder" {
  for_each = local.targets_creating_repo

  name                 = "aws-lambda/nullplatform-lambda-placeholder"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    ManagedBy    = "nullplatform-package-installation"
    Package      = var.installation.package_slug
    Installation = var.installation.id
    Target       = each.key
  }
}

# ── Platform plane, once per installation ──

resource "nullplatform_scope_type" "this" {
  count = var.scope_type.id == null ? 1 : 0

  nrn           = var.installation.nrn
  name          = var.scope_type.name
  description   = var.scope_type.description
  provider_type = "service"
  provider_id   = var.service_specification_id
}

resource "nullplatform_provider_specification" "scope_configuration" {
  count = var.scope_configuration.id == null ? 1 : 0

  name             = local.scope_configuration_template.name
  description      = local.scope_configuration_template.description
  category         = local.scope_configuration_template.category
  icon             = local.scope_configuration_template.icon
  allow_dimensions = local.scope_configuration_template.allow_dimensions
  visible_to       = [var.installation.nrn]
  schema           = jsonencode(local.scope_configuration_template.schema)
}

# Which providers serve this scope type's metrics and logs. No resource writes
# NRN settings; the script merges these two keys, as scope_definition does.
resource "terraform_data" "nrn_settings" {
  triggers_replace = {
    nrn              = var.installation.nrn
    slug             = var.installation.package_slug
    metrics_provider = var.metrics_provider
    log_provider     = var.log_provider
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/nrn_settings"
    environment = {
      NRN              = self.triggers_replace.nrn
      SLUG             = self.triggers_replace.slug
      METRICS_PROVIDER = self.triggers_replace.metrics_provider
      LOG_PROVIDER     = self.triggers_replace.log_provider
    }
  }
}

# ── Platform plane, once per target ──

# The scope-configuration values the runtime reads by dimensions.
resource "nullplatform_provider_config" "scope_configuration" {
  for_each = local.targets_creating_configuration

  nrn        = var.installation.nrn
  type       = var.scope_configuration.slug
  dimensions = each.value.dimensions
  attributes = jsonencode({
    state      = { tofu_state_bucket = local.state_bucket[each.key], tofu_state_bucket_region = var.aws_region }
    deployment = { placeholder_image_uri = local.placeholder_image_uri[each.key] }
  })

  depends_on = [nullplatform_provider_specification.scope_configuration]
}

# A target with no IAM provider gets one, owned here, holding only this entry.
resource "nullplatform_provider_config" "iam" {
  for_each = local.targets_creating_provider

  nrn        = var.installation.nrn
  type       = "aws-iam-configuration"
  dimensions = each.value.dimensions
  attributes = jsonencode({
    iam_role_arns = { arns = [{ selector = "lambda", arn = local.role_arn[each.key] }] }
  })
}

# An existing IAM provider gets exactly one entry added, removed on destroy.
# Script until the API has an entry endpoint; a nullplatform_iam_role_entry
# resource would swap in here.
resource "terraform_data" "iam_role_entry" {
  for_each = local.targets_writing_entry

  triggers_replace = {
    provider_id = each.value.iam_provider_id
    selector    = "lambda"
    arn         = local.role_arn[each.key]
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/iam_role_entry upsert \"$PROVIDER_ID\" \"$SELECTOR\" \"$ROLE_ARN\""
    environment = {
      PROVIDER_ID = self.triggers_replace.provider_id
      SELECTOR    = self.triggers_replace.selector
      ROLE_ARN    = self.triggers_replace.arn
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/scripts/iam_role_entry remove \"$PROVIDER_ID\" \"$SELECTOR\""
    environment = {
      PROVIDER_ID = self.triggers_replace.provider_id
      SELECTOR    = self.triggers_replace.selector
    }
  }
}

# ── The agent channel: package-exec to the package worker ──

resource "nullplatform_notification_channel" "worker" {
  count = var.create_channel && var.channel_id == null ? 1 : 0

  nrn         = var.installation.nrn
  type        = "agent"
  source      = ["service", "telemetry"]
  description = "${var.installation.package_slug} worker (${local.installation_suffix})" # the API caps it at 64 characters

  configuration {
    agent {
      selector = var.agent.tags
      command {
        type = "package-exec"
        data = {
          package = var.installation.package_slug
          cmdline = "/app/packages/${var.installation.package_slug}/entrypoint"
          environment = jsonencode({
            NP_ACTION_CONTEXT = "'$${NOTIFICATION_CONTEXT}'"
            NP_PLUGIN         = var.installation.package_slug
          })
        }
      }
    }
  }

  filters = jsonencode({
    "$or" = [
      { "service.specification.slug" = { "$eq" = var.installation.package_slug } },
      { "arguments.scope_provider" = { "$eq" = var.service_specification_id } },
    ]
  })
}
