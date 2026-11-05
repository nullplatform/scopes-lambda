################################################################################
# aws-lambda scope — installation, platform plane
#
# What the scope needs once per installation on the platform side: the scope
# type, the scope-configuration schema and the NRN settings. Everything that
# is per account or per environment (role, state bucket, placeholder, IAM
# provider entry, scope-configuration values, and the agent channel, since
# the agent is per account) is target/, instantiated once per account by the
# caller with the right AWS provider.
#
# Ownership: what is created here is owned, and destroy removes it; what the
# caller names (an existing scope type or schema) is reused and left alone.
################################################################################

locals {
  # The scope's own template, read as is: only the NRN placeholder is filled.
  scope_configuration_template = jsondecode(replace(
    file("${path.module}/${var.scope_configuration_template}"),
    "{{ env.Getenv \"NRN\" }}", var.installation.nrn,
  ))

  scope_type_id                        = coalesce(var.scope_type_id, try(tostring(nullplatform_scope_type.this[0].id), null))
  scope_configuration_specification_id = coalesce(var.scope_configuration_specification_id, try(nullplatform_provider_specification.scope_configuration[0].id, null))
}

resource "nullplatform_scope_type" "this" {
  count = var.scope_type_id == null ? 1 : 0

  nrn           = var.installation.nrn
  name          = var.scope_type_name
  description   = var.scope_type_description
  provider_type = "service"
  provider_id   = var.service_specification_id
}

resource "nullplatform_provider_specification" "scope_configuration" {
  count = var.scope_configuration_specification_id == null ? 1 : 0

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
