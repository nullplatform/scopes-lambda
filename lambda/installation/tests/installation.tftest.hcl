mock_provider "aws" {
  mock_data "aws_caller_identity" {
    # Any string does for a plan: the bucket name only has to carry it.
    defaults = {
      account_id = "example-account"
    }
  }
}
mock_provider "nullplatform" {}

# What lib/context hands over for a fresh organization with two environments
# where nothing exists yet: everything is created. The runs below vary what
# was found or given.
variables {
  installation = {
    id           = "0f4c2d1e-aaaa-bbbb-cccc-000000000001"
    nrn          = "organization=1:account=2"
    package_slug = "nullplatform-aws-lambda"
    version      = "0.12.2"
  }
  agent = {
    role_arn = "arn:aws:iam::123456789012:role/nullplatform-agent-role"
    tags     = { environment = "development" }
  }
  service_specification_id = "spec-lambda"
  scope_type               = { name = "nullplatform AWS Lambda", description = "Serverless functions on AWS Lambda" }
  scope_configuration      = { slug = "aws-lambda" }
  targets = {
    development = { dimensions = { environment = "development" } }
    production  = { dimensions = { environment = "production" } }
  }
}

run "a_fresh_organization_gets_everything_created_and_the_image_reported_missing" {
  command = plan

  assert {
    condition     = length(aws_iam_role.lambda) == 2 && length(aws_s3_bucket.state) == 2 && length(aws_ecr_repository.placeholder) == 2 && length(nullplatform_provider_config.iam) == 2
    error_message = "With nothing given, every target gets a role, a state bucket, a placeholder repository and an IAM provider"
  }

  assert {
    condition     = length(nullplatform_scope_type.this) == 1 && length(nullplatform_provider_specification.scope_configuration) == 1 && length(nullplatform_notification_channel.worker) == 1
    error_message = "With nothing found, the scope type, the schema and the channel are created once"
  }

  assert {
    condition     = length(nullplatform_provider_config.scope_configuration) == 0 && length([for m in output.missing : m if m.need == "placeholder_image"]) == 2
    error_message = "The image is never built here: no scope-configuration can be written yet, and the placeholder is reported missing per target"
  }

  assert {
    condition     = aws_s3_bucket.state["production"].bucket == "nullplatform-lambda-tfstate-example-account-0f4c2d1e-production"
    error_message = "State buckets are named under the prefix the storage policy covers, with the account, the installation and the target"
  }

  assert {
    condition     = nullplatform_scope_type.this[0].provider_id == "spec-lambda" && nullplatform_scope_type.this[0].provider_type == "service"
    error_message = "The scope type delegates to the package's specification"
  }

  assert {
    condition     = nullplatform_provider_specification.scope_configuration[0].name == "AWS Lambda" && nullplatform_provider_specification.scope_configuration[0].visible_to == tolist(["organization=1:account=2"])
    error_message = "The schema comes from the scope's own template, visible at the installation NRN"
  }
}

run "an_already_configured_organization_is_adopted_and_nothing_is_created" {
  command = plan

  variables {
    scope_type          = { id = "st-existing", name = "nullplatform AWS Lambda", description = "Serverless functions on AWS Lambda" }
    scope_configuration = { id = "ps-existing", slug = "aws-lambda" }
    channel_id          = "ch-existing"
    targets = {
      default = {
        dimensions             = {}
        role_arn               = "arn:aws:iam::123456789012:role/their-lambda-role"
        role_from_entry        = true
        iam_provider_id        = "prov-existing"
        state_bucket           = "their-state-bucket"
        placeholder_image_uri  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
        scope_configuration_id = "sc-existing"
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.lambda) == 0 && length(aws_s3_bucket.state) == 0 && length(aws_ecr_repository.placeholder) == 0 && length(nullplatform_provider_config.iam) == 0 && length(terraform_data.iam_role_entry) == 0
    error_message = "A role found under selector lambda is adopted: no role, no entry, no provider created"
  }

  assert {
    condition     = length(nullplatform_scope_type.this) == 0 && length(nullplatform_provider_specification.scope_configuration) == 0 && length(nullplatform_provider_config.scope_configuration) == 0 && length(nullplatform_notification_channel.worker) == 0
    error_message = "Found scope type, schema, scope-configuration and channel are adopted, not recreated"
  }

  assert {
    condition     = alltrue([for r in output.resources : r.ownership != "owned" if r.type != "nrn_settings"])
    error_message = "The report must mark everything but the NRN settings as adopted or provided"
  }

  assert {
    condition     = length([for m in output.missing : m if m.need != "alb_listener"]) == 0
    error_message = "Nothing but the optional ALB may be missing"
  }
}

run "a_provided_role_in_an_existing_provider_gets_one_entry_and_a_scope_configuration_once_the_image_is_known" {
  command = plan

  variables {
    targets = {
      production = {
        dimensions            = { environment = "production" }
        role_arn              = "arn:aws:iam::123456789012:role/their-lambda-role"
        iam_provider_id       = "prov-existing"
        placeholder_image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.lambda) == 0 && length(terraform_data.iam_role_entry) == 1 && terraform_data.iam_role_entry["production"].triggers_replace.selector == "lambda"
    error_message = "A provided role is registered as one entry in the existing provider, not created"
  }

  assert {
    condition     = length(aws_s3_bucket.state) == 1 && length(nullplatform_provider_config.scope_configuration) == 1 && nullplatform_provider_config.scope_configuration["production"].type == "aws-lambda"
    error_message = "With the image known, the state bucket is created and the scope-configuration written for the target's dimensions"
  }

  assert {
    condition     = can(regex("nullplatform-lambda-tfstate-example-account-0f4c2d1e-production", nullplatform_provider_config.scope_configuration["production"].attributes))
    error_message = "The scope-configuration points at the created state bucket"
  }
}

run "the_channel_can_be_left_to_the_organization" {
  command = plan

  variables {
    create_channel = false
  }

  assert {
    condition     = length(nullplatform_notification_channel.worker) == 0
    error_message = "With create_channel = false no channel may be created"
  }
}
