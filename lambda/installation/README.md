# scopes-lambda installation

OpenTofu module that installs the `nullplatform-aws-lambda` package (specification "nullplatform AWS Lambda") in your organization, at the version of the tag you reference. The package is published once for every organization and brings the scope specification and its action specifications, read-only. This module creates what each organization owns on top of it, from the templates of that tag:

1. The installation of the package at `nrn`.
2. The scope type, pointing at the package's specification.
3. The NRN settings that pick the scope's metrics and logs providers.
4. The scope-configuration provider specification (the schema of the OpenTofu state bucket, placeholder image and agent layer settings).

It is only the nullplatform side of the installation, so it goes in the layer of your stack that registers specifications. The AWS requirements and the agent channel stay in the layers that already hold them. See [Install in your organization](../../README.md#install-in-your-organization) for the three layers together.

## Usage

```hcl
module "lambda" {
  source = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=v0.11.1"

  nrn = "organization=123:account=456"
}
```

**Upgrade**: move `ref` to a newer tag and apply. New scopes are born with the new version; existing scopes keep theirs until they are moved one by one.

## Prerequisites

- **Providers**: an AWS cloud provider, configured at `nrn` or above it.
- **Tools on the machine running the apply**: `np` (the NRN settings patch).
- **Credentials for the apply**: a nullplatform API key (`NULLPLATFORM_API_KEY` for the provider, `NP_API_KEY` or `np_api_key` for `np`) that can install packages and create scope types and provider specifications at `nrn`.

## Inputs

| Name | Description | Default |
|---|---|---|
| `nrn` | NRN of your organization where the scope is installed | required |
| `visible_to` | Where inside your organization the scope can be used | `[nrn]` |
| `np_api_key` | API key for `np nrn patch` | `NP_API_KEY` of the environment |
| `external_metrics_provider` | Metrics provider in the NRN settings | `externalmetrics` |
| `external_logging_provider` | Logs provider in the NRN settings | `external` |
| `scope_type_name` | Name of the scope type; change it when your organization already has an "AWS Lambda" one | `AWS Lambda` |
| `scope_type_description` | Description of the scope type | `Serverless functions on AWS Lambda` |
| `create_scope_configuration` | Create the scope-configuration specification (false to keep the one you already have) | `true` |
| `scope_configuration_name` | Name of the scope-configuration specification, when the template's collides | `AWS Lambda` |

## Outputs

| Name | Description |
|---|---|
| `service_specification_id` | Id of the scope specification: the channel's `scope_specification_id` (also `service_slug` for the slug) |
| `service_specification_slug` | Slug of the scope specification: what the agent channel filters on |
| `package_slug` | Slug of the package: the `package_slug` of the agent channel |
| `scope_configuration_specification_slug` | The `type` of the provider config with the scope's settings (also `provider_specification_slug`; null with `create_scope_configuration = false`) |
| `scope_configuration_specification_id` | Id of the scope-configuration provider specification |
| `scope_type_id` | Id of the scope type in your organization |
| `package_id` | Id of the installed package |
| `installed_version` | Version new scopes are born with (also `package_default_version`) |
| `installation_id` | Id of the package installation |
| `missing_optional_requirements` | Optional providers the package can use that you have not configured |

## What stays the publisher's

The specification is shared by every organization, so its options are the published ones. In particular, `LAMBDA_DEPLOYMENT_TYPES` (which package types the form offers) is decided when the package is published.

Already registered this scope with `lambda/specs/install`? Both can live in one organization: see [Already registered with `specs/install`?](../../README.md#already-registered-with-specsinstall).

Use this module to keep receiving updates. Fork the repository only when you need to extend the scope substantially; see [Global package or fork?](../../README.md#global-package-or-fork) for what a fork costs.
