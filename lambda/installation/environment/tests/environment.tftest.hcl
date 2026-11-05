# Only the platform provider: an environment has no cloud resources of its
# own, it registers the account's.
mock_provider "nullplatform" {}

variables {
  installation = {
    id           = "0f4c2d1e-aaaa-bbbb-cccc-000000000001"
    nrn          = "organization=1:account=2"
    package_slug = "nullplatform-aws-lambda"
    version      = "0.12.2"
  }
  name                     = "production"
  dimensions               = { environment = "production" }
  role_arn                 = "arn:aws:iam::123456789012:role/nullplatform-nullplatform-aws-lambda-0f4c2d1e-prod"
  state_bucket             = "nullplatform-lambda-tfstate-0f4c2d1e-abc123"
  state_bucket_region      = "us-east-1"
  agent_tags               = { environment = "production" }
  service_specification_id = "spec-lambda"
  scope_configuration_slug = "aws-lambda"
}

run "nothing_given_creates_the_iam_provider_and_the_channel_and_waits_for_the_image" {
  command = plan

  assert {
    condition     = length(nullplatform_provider_config.iam) == 1 && length(terraform_data.iam_role_entry) == 0 && length(nullplatform_notification_channel.worker) == 1
    error_message = "With no IAM provider given, one is created holding the account's role; the channel is created"
  }

  assert {
    condition     = nullplatform_provider_config.iam[0].dimensions == tomap({ environment = "production" }) && can(regex("0f4c2d1e-prod", nullplatform_provider_config.iam[0].attributes))
    error_message = "The IAM provider carries the environment's dimensions and names the account's role under selector lambda"
  }

  assert {
    condition     = length(nullplatform_provider_config.scope_configuration) == 0 && length([for m in output.missing : m if m.need == "scope_configuration"]) == 1
    error_message = "Without the placeholder image no scope-configuration can be written yet, and it is reported missing"
  }
}

run "the_channel_selects_this_environments_agent_and_only_routes_its_dimensions" {
  command = plan

  assert {
    condition     = nullplatform_notification_channel.worker[0].configuration[0].agent[0].selector == tomap({ environment = "production" })
    error_message = "The channel selects the agent by its tags"
  }

  assert {
    condition     = can(regex("scope\\.dimensions\\.environment", nullplatform_notification_channel.worker[0].filters)) && can(regex("\"production\"", nullplatform_notification_channel.worker[0].filters)) && can(regex("spec-lambda", nullplatform_notification_channel.worker[0].filters))
    error_message = "With dimensions, the channel routes only scopes in them, besides the package's specification"
  }
}

run "an_environment_without_dimensions_routes_every_scope_of_the_package" {
  command = plan

  variables {
    name       = "default"
    dimensions = {}
  }

  assert {
    condition     = !can(regex("dimensions", nullplatform_notification_channel.worker[0].filters))
    error_message = "Without dimensions the channel has no dimension filter"
  }
}

run "two_environments_in_one_account_share_the_role_and_differ_only_on_the_platform" {
  command = plan

  variables {
    name       = "staging"
    dimensions = { environment = "staging" }
    agent_tags = { environment = "development" } # the development account's agent serves staging too
  }

  assert {
    condition     = nullplatform_provider_config.iam[0].dimensions == tomap({ environment = "staging" }) && can(regex("0f4c2d1e-prod", nullplatform_provider_config.iam[0].attributes))
    error_message = "A second environment registers the same account role under its own dimensions, creating nothing in the cloud"
  }

  assert {
    condition     = nullplatform_notification_channel.worker[0].configuration[0].agent[0].selector == tomap({ environment = "development" }) && can(regex("\"staging\"", nullplatform_notification_channel.worker[0].filters))
    error_message = "Its channel selects the shared agent but routes only staging scopes"
  }
}

run "everything_given_creates_nothing" {
  command = plan

  variables {
    role_from_entry        = true
    iam_provider_id        = "prov-existing"
    placeholder_image_uri  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
    scope_configuration_id = "sc-existing"
    channel_id             = "ch-existing"
  }

  assert {
    condition     = length(nullplatform_provider_config.iam) == 0 && length(terraform_data.iam_role_entry) == 0 && length(nullplatform_provider_config.scope_configuration) == 0 && length(nullplatform_notification_channel.worker) == 0
    error_message = "With everything given, nothing is created; a role that came from the IAM provider's own entry is not written back either"
  }

  assert {
    condition     = alltrue([for r in output.resources : r.ownership == "provided"]) && length(output.missing) == 0 && output.channel_id == "ch-existing" && output.iam_provider_id == "prov-existing"
    error_message = "The report marks everything as provided and nothing as missing"
  }
}

run "an_existing_provider_gets_one_entry_and_the_values_once_the_image_is_known" {
  command = plan

  variables {
    iam_provider_id       = "prov-existing"
    placeholder_image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
  }

  assert {
    condition     = length(nullplatform_provider_config.iam) == 0 && length(terraform_data.iam_role_entry) == 1 && terraform_data.iam_role_entry[0].triggers_replace.selector == "lambda"
    error_message = "The account's role is registered as one entry in the existing provider"
  }

  assert {
    condition     = length(nullplatform_provider_config.scope_configuration) == 1 && nullplatform_provider_config.scope_configuration[0].type == "aws-lambda" && can(regex("nullplatform-lambda-tfstate-0f4c2d1e-abc123", nullplatform_provider_config.scope_configuration[0].attributes)) && can(regex("us-east-1", nullplatform_provider_config.scope_configuration[0].attributes))
    error_message = "With the image known, the scope-configuration is written under the schema's slug, pointing at the account's bucket and region"
  }
}

run "the_channel_can_be_left_to_the_organization" {
  command = plan

  variables {
    create_channel = false
    agent_tags     = {}
  }

  assert {
    condition     = length(nullplatform_notification_channel.worker) == 0 && output.channel_id == null
    error_message = "With create_channel = false no channel may be created"
  }
}

run "creating_the_channel_needs_the_agent_tags" {
  command = plan

  variables {
    agent_tags = {}
  }

  expect_failures = [var.create_channel]
}
