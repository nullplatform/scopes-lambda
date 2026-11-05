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

variables {
  installation = {
    id           = "0f4c2d1e-aaaa-bbbb-cccc-000000000001"
    nrn          = "organization=1:account=2"
    package_slug = "nullplatform-aws-lambda"
    version      = "0.12.2"
  }
  name           = "prod"
  agent_role_arn = "arn:aws:iam::123456789012:role/nullplatform-agent-role"
}

run "nothing_given_creates_the_role_the_bucket_and_the_repository_and_reports_the_image_missing" {
  command = plan

  assert {
    condition     = length(aws_iam_role.lambda) == 1 && length(aws_s3_bucket.state) == 1 && length(aws_ecr_repository.placeholder) == 1
    error_message = "With nothing given, the role, the state bucket and the placeholder repository are created"
  }

  assert {
    condition     = length([for m in output.missing : m if m.need == "placeholder_image"]) == 1 && length([for m in output.missing : m if m.need == "alb_listener"]) == 1
    error_message = "The image is never built here and the ALB is the organization's: both are reported missing"
  }

  assert {
    condition     = aws_s3_bucket.state[0].bucket == "nullplatform-lambda-tfstate-0f4c2d1e-${substr(sha1("example-account-prod"), 0, 10)}" && length(aws_s3_bucket.state[0].bucket) <= 63
    error_message = "State buckets are named under the prefix the storage policy covers, with the installation and a hash of account id and name, within S3's 63 characters"
  }

  assert {
    condition     = can(regex("nullplatform-agent-role", aws_iam_role.lambda[0].assume_role_policy)) && aws_iam_role.lambda[0].name == "nullplatform-nullplatform-aws-lambda-0f4c2d1e-prod"
    error_message = "The created role trusts the agent role and is named by the installation and the account"
  }

  assert {
    condition     = output.state_bucket_region == "us-east-1"
    error_message = "The region is exported so environment/ can write it without an AWS provider"
  }
}

run "everything_given_creates_nothing" {
  command = plan

  variables {
    role_arn              = "arn:aws:iam::123456789012:role/their-lambda-role"
    state_bucket          = "their-state-bucket"
    placeholder_image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
    alb_listener_arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/their-alb/abc/def"
  }

  assert {
    condition     = length(aws_iam_role.lambda) == 0 && length(aws_s3_bucket.state) == 0 && length(aws_ecr_repository.placeholder) == 0
    error_message = "With everything given, nothing is created"
  }

  assert {
    condition     = alltrue([for r in output.resources : r.ownership == "provided"]) && length(output.missing) == 0
    error_message = "The report marks everything as provided and nothing as missing"
  }

  assert {
    condition     = output.role_arn == "arn:aws:iam::123456789012:role/their-lambda-role" && output.state_bucket == "their-state-bucket" && output.placeholder_repository_url == "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder"
    error_message = "The outputs hand the given values on to environment/, the repository taken from the image"
  }
}

run "an_existing_repository_without_an_image_is_reused" {
  command = plan

  variables {
    placeholder_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder"
  }

  assert {
    condition     = length(aws_ecr_repository.placeholder) == 0 && length([for m in output.missing : m if m.need == "placeholder_image"]) == 1
    error_message = "A given repository is not created again, and the image is still reported missing"
  }
}
