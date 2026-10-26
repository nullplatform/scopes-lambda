# scopes-lambda installation

OpenTofu module that installs the `scopes-lambda` package in your organization. The package is published once for every organization and brings the scope specification and its action specifications, read-only. This module creates, in your accounts, what each organization needs on top of it:

1. The AWS permissions role the scope assumes, its policies, the placeholder ECR repository and, optionally, a public ALB ([`../specs/requirements`](../specs/requirements)).
2. The installation of the package at `nrn`, at the version of the tag you reference.
3. The scope type, pointing at the package's specification.
4. The NRN settings that pick the scope's metrics and logs providers.
5. The scope-configuration provider specification (the schema of the OpenTofu state bucket, placeholder image and agent layer settings).
6. The agent notification channel that routes the scope's actions to the package worker.

## Usage

```hcl
terraform {
  required_providers {
    aws          = { source = "hashicorp/aws", version = ">= 5.0" }
    nullplatform = { source = "nullplatform/nullplatform", version = ">= 0.0.110" }
  }
}

# AWS credentials come from the environment (profile, SSO or role); nullplatform
# from NULLPLATFORM_API_KEY (and NP_API_KEY for `np`), a key with package:create
# at the NRN.
provider "aws" {
  region = "us-east-1"
}
provider "nullplatform" {}

locals {
  nrn = "organization=123:account=456"
}

# 1. Install the scope: AWS requirements, installation of the global package,
#    scope type, NRN settings, scope-configuration schema and agent channel.
module "lambda_scope" {
  source = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=v0.11.1"

  nrn                  = local.nrn
  cluster_name         = "my-cluster"            # names the role nullplatform_my-cluster_lambda_role
  agent_tags_selectors = { cluster = "runtime" } # must match the agent's TAGS
}

# 2. Register the role in the NRN's AWS IAM provider, under the selector the
#    scope looks up ("lambda"). One aws-iam-configuration per NRN and dimensions:
#    if you already have one, add this entry to its list instead.
resource "nullplatform_provider_config" "aws_iam" {
  nrn  = local.nrn
  type = "aws-iam-configuration"
  attributes = jsonencode({
    iam_role_arns = {
      arns = [
        { selector = "lambda", arn = module.lambda_scope.permissions_role_arn },
      ]
    }
  })
}

# 3. The scope's settings, in a provider of the schema the module created.
#    The placeholder image is the one you publish with lambda/scope/placeholder/publish
#    to the repository the module created, tagged -arm64 and -amd64: point at
#    either one and the agent swaps the suffix to match each scope's architecture.
resource "nullplatform_provider_config" "lambda_scope_configuration" {
  nrn  = local.nrn
  type = module.lambda_scope.scope_configuration_specification_slug
  attributes = jsonencode({
    state = {
      tofu_state_bucket = "my-tofu-state-bucket"
    }
    deployment = {
      placeholder_image_uri = "${module.lambda_scope.placeholder_image_repository_url}:latest-arm64"
    }
  })
}

output "lambda_installed_version" {
  value = module.lambda_scope.installed_version
}
```

Steps 2 and 3 are yours, not the module's: the scope assumes the role it finds under selector `lambda` in the NRN's `aws-iam-configuration` provider, which belongs to your stack and is shared with other services, and its settings (OpenTofu state bucket, placeholder image) are your account's. Zip scopes need no placeholder image; Image scopes need one published to `placeholder_image_repository_url`. With `install_alb = true`, also publish `lambda_alb_listener_arn` to your `aws-networking-configuration` provider (`load_balancer.public.listener_arn`).

**Upgrade**: move `ref` to a newer tag and apply. New scopes are born with the new version; existing scopes keep theirs until they are moved one by one.

## Prerequisites

- **Agent**: running in your cluster with `TAGS` matching `agent_tags_selectors`, and `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries`.
- **Agent IAM role**: allowed to `sts:AssumeRole` the role this module creates (`nullplatform_<cluster_name>_lambda_role` by default).
- **Providers**: an AWS cloud provider, configured at `nrn` or above it.
- **Tools on the machine running the apply**: `np` (the NRN settings patch), `gomplate` and `jq` (the agent channel template).
- **Credentials for the apply**: AWS credentials that can create IAM roles, policies and ECR repositories, and a nullplatform API key (`NULLPLATFORM_API_KEY` for the provider, `NP_API_KEY` or `np_api_key` for `np`) that can install packages and create scope types, provider specifications and notification channels at `nrn`.

## Inputs

| Name | Description | Default |
|---|---|---|
| `nrn` | NRN of your organization where the scope is installed | required |
| `agent_tags_selectors` | Tags that select the agent (must match its `TAGS`) | required |
| `cluster_name` | Cluster where the agent runs; names the IAM role, policies and ALB | required |
| `visible_to` | Where inside your organization the scope can be used | `[nrn]` |
| `np_api_key` | API key for `np nrn patch` | `NP_API_KEY` of the environment |
| `external_metrics_provider` | Metrics provider in the NRN settings | `externalmetrics` |
| `external_logging_provider` | Logs provider in the NRN settings | `external` |
| `scope_configuration_name` | Name of the scope-configuration specification, when the template's collides | `AWS Lambda` |
| `agent_role_arn` | Agent role trusted by the permissions role | `nullplatform-<cluster_name>-agent-role` |
| `additional_agent_role_arns` | Extra roles allowed to assume the permissions role | `[]` |
| `iam_create_role` | Create the IAM role, policies and placeholder repository | `true` |
| `iam_role_name` | Name of the IAM role | `nullplatform_<cluster_name>_lambda_role` |
| `iam_policies_name_prefix` | Prefix of the IAM policy names | `nullplatform_<cluster_name>` |
| `iam_resource_tags` | Tags on every IAM resource | `{}` |
| `placeholder_repository_name` | Private ECR repository of the placeholder image | `aws-lambda/nullplatform-lambda-placeholder` |
| `assets_bucket_name` | S3 bucket of the Lambda deployment assets | `lambda-files-aws-services` |
| `install_alb` | Create a public ALB for HTTP functions | `false` |
| `vpc_id`, `public_subnet_ids`, `public_zone_id`, `domain_name`, `certificate_arn`, `alb_name` | ALB settings (see [`../specs/requirements`](../specs/requirements)) | — |

## Outputs

| Name | Description |
|---|---|
| `permissions_role_arn` | Role to add to your AWS IAM provider with selector `lambda` |
| `placeholder_image_repository_url` | Where to publish the placeholder image for Image scopes |
| `lambda_alb_listener_arn` | HTTPS listener of the ALB (empty without `install_alb`) |
| `installation_id` | Id of the package installation |
| `installed_version` | Version new scopes are born with |
| `missing_optional_requirements` | Optional providers the package can use that you have not configured |
| `scope_type_id` | Id of the scope type in your organization |
| `scope_configuration_specification_id` | Id of the scope-configuration provider specification |
| `scope_configuration_specification_slug` | Its slug: the `type` of the provider config with the scope's settings |
| `notification_channel_id` | Id of the agent notification channel |

## What stays the publisher's

The specification is shared by every organization, so its options are the published ones. In particular, `LAMBDA_DEPLOYMENT_TYPES` (which package types the form offers) is decided when the package is published.

Use this module to keep receiving updates. Fork the repository only when you need to extend the scope substantially; see [Global package or fork?](../../README.md#global-package-or-fork) for what a fork costs.
