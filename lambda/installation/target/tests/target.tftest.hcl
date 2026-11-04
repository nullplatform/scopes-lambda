mock_provider "aws" {
  mock_data "aws_caller_identity" {
    # Any string does for a plan: the bucket name only has to carry it.
    defaults = {
      account_id = "example-account"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}
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
  agent_role_arn           = "arn:aws:iam::123456789012:role/nullplatform-agent-role"
  scope_configuration_slug = "aws-lambda"
}

run "nothing_given_creates_everything_and_reports_the_image_missing" {
  command = plan

  assert {
    condition     = length(aws_iam_role.lambda) == 1 && length(aws_s3_bucket.state) == 1 && length(aws_ecr_repository.placeholder) == 1 && length(nullplatform_provider_config.iam) == 1
    error_message = "With nothing given, the role, the state bucket, the placeholder repository and an IAM provider are created"
  }

  assert {
    condition     = length(nullplatform_provider_config.scope_configuration) == 0 && length([for m in output.missing : m if m.need == "placeholder_image"]) == 1
    error_message = "The image is never built here: no scope-configuration can be written yet, and the placeholder is reported missing"
  }

  assert {
    condition     = aws_s3_bucket.state[0].bucket == "nullplatform-lambda-tfstate-0f4c2d1e-${substr(sha1("example-account-production"), 0, 10)}" && length(aws_s3_bucket.state[0].bucket) <= 63
    error_message = "State buckets are named under the prefix the storage policy covers, with the installation and a hash of account and target, within S3's 63 characters"
  }

  assert {
    condition     = can(regex("nullplatform-agent-role", aws_iam_role.lambda[0].assume_role_policy))
    error_message = "The created role must trust the agent role"
  }
}

run "everything_given_creates_nothing" {
  command = plan

  variables {
    role_arn               = "arn:aws:iam::123456789012:role/their-lambda-role"
    role_from_entry        = true
    iam_provider_id        = "prov-existing"
    state_bucket           = "their-state-bucket"
    placeholder_image_uri  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
    alb_listener_arn       = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/their-alb/abc/def"
    scope_configuration_id = "sc-existing"
  }

  assert {
    condition     = length(aws_iam_role.lambda) == 0 && length(aws_s3_bucket.state) == 0 && length(aws_ecr_repository.placeholder) == 0 && length(nullplatform_provider_config.iam) == 0 && length(terraform_data.iam_role_entry) == 0 && length(nullplatform_provider_config.scope_configuration) == 0
    error_message = "With everything given, nothing is created; a role that came from the IAM provider's own entry is not written back either"
  }

  assert {
    condition     = alltrue([for r in output.resources : r.ownership == "provided"]) && length(output.missing) == 0
    error_message = "The report marks everything as provided and nothing as missing"
  }
}

run "a_given_role_in_an_existing_provider_gets_one_entry_and_the_values_once_the_image_is_known" {
  command = plan

  variables {
    role_arn              = "arn:aws:iam::123456789012:role/their-lambda-role"
    iam_provider_id       = "prov-existing"
    placeholder_image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
  }

  assert {
    condition     = length(aws_iam_role.lambda) == 0 && length(terraform_data.iam_role_entry) == 1 && terraform_data.iam_role_entry[0].triggers_replace.selector == "lambda"
    error_message = "A given role is registered as one entry in the existing provider, not created"
  }

  assert {
    condition     = length(aws_s3_bucket.state) == 1 && length(nullplatform_provider_config.scope_configuration) == 1 && nullplatform_provider_config.scope_configuration[0].type == "aws-lambda" && can(regex("nullplatform-lambda-tfstate-0f4c2d1e-", nullplatform_provider_config.scope_configuration[0].attributes))
    error_message = "With the image known, the state bucket is created and the scope-configuration written under the schema's slug, pointing at that bucket"
  }
}
