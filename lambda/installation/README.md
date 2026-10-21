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
module "lambda_scope" {
  source = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=v0.10.0"

  nrn                  = "organization=123:account=456"
  cluster_name         = "my-cluster"
  agent_tags_selectors = { cluster = "runtime" }
}
```

After the apply:

- Add `module.lambda_scope.permissions_role_arn` to your AWS IAM provider with selector `lambda`.
- Configure a provider of the scope-configuration specification (`scope_configuration_specification_id`) with the OpenTofu state bucket and, for Image scopes, the placeholder image published to `placeholder_image_repository_url`.
- With `install_alb = true`, publish `lambda_alb_listener_arn` to your `aws-networking-configuration` provider.

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
| `notification_channel_id` | Id of the agent notification channel |

## What stays the publisher's

The specification is shared by every organization, so its options are the published ones. In particular, `LAMBDA_DEPLOYMENT_TYPES` (which package types the form offers) is decided when the package is published.

Use this module to keep receiving updates. Fork the repository only when you need to extend the scope substantially; see [Global package or fork?](../../README.md#global-package-or-fork) for what a fork costs.
