mock_provider "aws" {}

variables {
  iam_role_name                  = "lambda-execution-role"
  iam_create_role                = true
  iam_role_policies              = []
  iam_vpc_enabled                = false
  iam_role_entity                = "scope"
  iam_resource_tags_json         = {}
  iam_secrets_manager_secret_arn = ""
  lambda_role_arn                = ""
}

run "creates_iam_role" {
  command = plan

  assert {
    condition     = aws_iam_role.lambda[0].name == "lambda-execution-role"
    error_message = "Role name should be lambda-execution-role"
  }
}

run "sets_trust_policy_for_lambda" {
  command = plan

  assert {
    condition     = can(jsondecode(aws_iam_role.lambda[0].assume_role_policy))
    error_message = "Assume role policy should be valid JSON"
  }
}

run "attaches_basic_execution_policy" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 1
    error_message = "Should attach 1 managed policy (basic execution)"
  }
}

run "attaches_vpc_policy_when_vpc_enabled" {
  variables {
    iam_vpc_enabled = true
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 2
    error_message = "Should attach 2 managed policies (basic + VPC)"
  }
}

run "skips_vpc_policy_when_vpc_disabled" {
  variables {
    iam_vpc_enabled = false
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 1
    error_message = "Should attach only basic execution policy"
  }
}

run "creates_custom_inline_policies" {
  variables {
    iam_role_policies = [
      {
        name   = "custom-s3-policy"
        policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\"],\"Resource\":[\"arn:aws:s3:::my-bucket/*\"]}]}"
      }
    ]
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.custom) == 1
    error_message = "Should create 1 inline policy"
  }
}

run "creates_multiple_custom_policies" {
  variables {
    iam_role_policies = [
      {
        name   = "s3-policy"
        policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\"],\"Resource\":[\"arn:aws:s3:::bucket1/*\"]}]}"
      },
      {
        name   = "sqs-policy"
        policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"sqs:SendMessage\"],\"Resource\":[\"arn:aws:sqs:us-east-1:123456789012:my-queue\"]}]}"
      }
    ]
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.custom) == 2
    error_message = "Should create 2 inline policies"
  }
}

run "skips_custom_policies_when_empty" {
  variables {
    iam_role_policies = []
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.custom) == 0
    error_message = "Should not create inline policies when empty"
  }
}

run "creates_secrets_manager_policy_when_arn_provided" {
  variables {
    iam_secrets_manager_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:my-secret-abc123"
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.secrets_manager) == 1
    error_message = "Should create secrets manager policy"
  }
}

run "skips_secrets_manager_policy_when_no_arn" {
  variables {
    iam_secrets_manager_secret_arn = ""
  }
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.secrets_manager) == 0
    error_message = "Should not create secrets manager policy when ARN is empty"
  }
}

run "skips_role_creation_when_not_requested" {
  variables {
    iam_create_role = false
    lambda_role_arn = "arn:aws:iam::123456789012:role/existing-role"
  }
  command = plan

  assert {
    condition     = length(aws_iam_role.lambda) == 0
    error_message = "Should not create role when iam_create_role is false"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.managed) == 0
    error_message = "Should not attach policies when role is not created"
  }
}

run "applies_tags_to_role" {
  variables {
    iam_resource_tags_json = {
      Environment = "test"
      Project     = "lambda-scope"
    }
  }
  command = plan

  assert {
    condition     = aws_iam_role.lambda[0].tags["Environment"] == "test"
    error_message = "Environment tag should be 'test'"
  }

  assert {
    condition     = aws_iam_role.lambda[0].tags["Project"] == "lambda-scope"
    error_message = "Project tag should be 'lambda-scope'"
  }

  assert {
    condition     = aws_iam_role.lambda[0].tags["ManagedBy"] == "custom-scope-role"
    error_message = "ManagedBy tag should be 'custom-scope-role'"
  }
}

run "creates_role_with_custom_name" {
  variables {
    iam_role_name = "my-app-prod-lambda-role"
  }
  command = plan

  assert {
    condition     = aws_iam_role.lambda[0].name == "my-app-prod-lambda-role"
    error_message = "Role name should be my-app-prod-lambda-role"
  }
}

run "handles_max_length_role_name" {
  variables {
    # Exactly 64 characters - the AWS IAM role name limit
    iam_role_name = "acme-corp-production-my-application-api-scope-lambda-exec-role1"
  }
  command = plan

  assert {
    condition     = aws_iam_role.lambda[0].name == "acme-corp-production-my-application-api-scope-lambda-exec-role1"
    error_message = "Should accept role names up to 64 characters"
  }
}
