mock_provider "nullplatform" {}

variables {
  installation = {
    id           = "0f4c2d1e-aaaa-bbbb-cccc-000000000001"
    nrn          = "organization=1:account=2"
    package_slug = "nullplatform-aws-lambda"
    version      = "0.12.2"
  }
  service_specification_id = "spec-lambda"
}

run "nothing_given_creates_the_scope_type_and_the_schema" {
  command = plan

  assert {
    condition     = length(nullplatform_scope_type.this) == 1 && nullplatform_scope_type.this[0].provider_id == "spec-lambda" && nullplatform_scope_type.this[0].provider_type == "service"
    error_message = "The scope type delegates to the package's specification"
  }

  assert {
    condition     = length(nullplatform_provider_specification.scope_configuration) == 1 && nullplatform_provider_specification.scope_configuration[0].name == "AWS Lambda" && nullplatform_provider_specification.scope_configuration[0].visible_to == tolist(["organization=1:account=2"])
    error_message = "The schema comes from the scope's own template, visible at the installation NRN"
  }

  assert {
    condition     = terraform_data.nrn_settings.triggers_replace.slug == "nullplatform-aws-lambda"
    error_message = "The NRN settings are keyed by the package slug"
  }
}

run "given_ids_are_reused_and_reported_as_provided" {
  command = plan

  variables {
    scope_type_id                        = "st-given"
    scope_configuration_specification_id = "ps-given"
  }

  assert {
    condition     = length(nullplatform_scope_type.this) == 0 && length(nullplatform_provider_specification.scope_configuration) == 0
    error_message = "Given ids must not be created again"
  }

  assert {
    condition     = output.scope_type_id == "st-given" && output.scope_configuration_specification_id == "ps-given" && output.scope_configuration_slug == null
    error_message = "The outputs hand the given ids on; the slug of a given schema is the caller's to pass to target/"
  }

  assert {
    condition     = alltrue([for r in output.resources : r.ownership == "provided" if r.type != "nrn_settings"])
    error_message = "The report must mark given ids as provided"
  }
}
