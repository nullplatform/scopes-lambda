# Installation

Everything this scope needs installed in an organization, written by the
package as OpenTofu modules the organization calls from its own Terraform, the
way it calls any vendor's module. It crosses the layers on purpose: an
installation is exactly a change that touches the cloud account and the
platform at once, so the modules are cut by what they touch, not by layer.

```
installation/              module, once per installation: scope type, scope-configuration schema, NRN settings     (nullplatform provider)
installation/account/      module, once per AWS account: the worker's role, the scopes' state bucket, the placeholder repository   (aws provider)
installation/environment/  module, once per dimension set: IAM provider entry, scope-configuration values, agent channel   (nullplatform provider)
installation/run/          a runner root for installing without a Terraform repository (np package install, or by hand)
```

`account` and `environment` are separate because they are counted
differently: an organization with development and staging in one account
and production in another has two accounts and three environments. Each
environment takes the outputs of the account it runs in, so two environments
in one account never create a second role, bucket or repository, and the
placeholder repository, which has one name per account, is created once.

## From the organization's Terraform

One module call for the platform side, one per account with that account's
AWS provider, one per environment with the account's outputs. Nothing to copy
from this repository, nothing in a bindings or an infrastructure layer:

```hcl
provider "nullplatform" {}                     # NULLPLATFORM_API_KEY from the environment
provider "aws" { alias = "dev";  region = "us-east-1"; profile = "dev" }
provider "aws" { alias = "prod"; region = "us-east-1"; assume_role { role_arn = "arn:aws:iam::123456789012:role/platform-admin" } }

locals {
  lambda_installation = { id = nullplatform_package_installation.lambda.id, nrn = var.nrn, package_slug = "nullplatform-aws-lambda", version = "0.12.2" }
}

module "lambda" {                                               # once
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=v0.12.2"
  installation             = local.lambda_installation
  service_specification_id = data.nullplatform_service_specification.lambda.id
  # scope_configuration_specification_id = "…"   reuse the copy's schema instead of creating one
}

module "lambda_account_dev" {                                   # once per account
  source                = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/account?ref=v0.12.2"
  providers             = { aws = aws.dev }
  installation          = local.lambda_installation
  name                  = "dev"
  agent_role_arn        = module.agent_dev.role_arn
  placeholder_image_uri = "111111111111.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
}

module "lambda_account_prod" {
  source                = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/account?ref=v0.12.2"
  providers             = { aws = aws.prod }
  installation          = local.lambda_installation
  name                  = "prod"
  agent_role_arn        = module.agent_prod.role_arn
  role_arn              = "arn:aws:iam::123456789012:role/their-lambda-role"   # bring your own
  state_bucket          = "their-lambda-tfstate"
  placeholder_image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
  alb_listener_arn      = module.bindings.lambda_alb_listener_arn
}

module "lambda_development" {                                   # once per environment, from its account
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/environment?ref=v0.12.2"
  installation             = local.lambda_installation
  name                     = "development"
  dimensions               = { environment = "development" }
  role_arn                 = module.lambda_account_dev.role_arn
  state_bucket             = module.lambda_account_dev.state_bucket
  state_bucket_region      = module.lambda_account_dev.state_bucket_region
  placeholder_image_uri    = module.lambda_account_dev.placeholder_image_uri
  agent_tags               = { environment = "development" }   # the dev account's agent; the channel routes only development scopes to it
  service_specification_id = data.nullplatform_service_specification.lambda.id
  scope_configuration_slug = module.lambda.scope_configuration_slug
}

module "lambda_staging" {                                       # same account as development: nothing new in the cloud
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/environment?ref=v0.12.2"
  installation             = local.lambda_installation
  name                     = "staging"
  dimensions               = { environment = "staging" }
  role_arn                 = module.lambda_account_dev.role_arn
  state_bucket             = module.lambda_account_dev.state_bucket
  state_bucket_region      = module.lambda_account_dev.state_bucket_region
  placeholder_image_uri    = module.lambda_account_dev.placeholder_image_uri
  agent_tags               = { environment = "development" }
  service_specification_id = data.nullplatform_service_specification.lambda.id
  scope_configuration_slug = module.lambda.scope_configuration_slug
}

module "lambda_production" {
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/environment?ref=v0.12.2"
  installation             = local.lambda_installation
  name                     = "production"
  dimensions               = { environment = "production" }
  role_arn                 = module.lambda_account_prod.role_arn
  state_bucket             = module.lambda_account_prod.state_bucket
  state_bucket_region      = module.lambda_account_prod.state_bucket_region
  placeholder_image_uri    = module.lambda_account_prod.placeholder_image_uri
  agent_tags               = { environment = "production" }
  service_specification_id = data.nullplatform_service_specification.lambda.id
  scope_configuration_slug = module.lambda.scope_configuration_slug
  iam_provider_id          = module.bindings.iam_provider_prod_id         # register in an existing provider; null creates one
}
```

Each requirement is **received as a parameter** or **provisioned here**:

| Requirement | Module | Parameter | When absent |
|---|---|---|---|
| Scope type | `installation` | `scope_type_id` | created with `scope_type_name` |
| Scope-configuration schema | `installation` | `scope_configuration_specification_id` | created from `specs/scope-configuration.json.tpl` |
| NRN settings (metrics and logs providers) | `installation` | `metrics_provider`, `log_provider` | written with the defaults |
| Role the worker assumes | `account` | `role_arn` | created, trusting `agent_role_arn` |
| State bucket | `account` | `state_bucket` | created |
| Placeholder image | `account` | `placeholder_image_uri` | **never built here**: the repository is created (or `placeholder_repository_url` reused) and the image reported in `missing` |
| ALB listener (optional) | `account` | `alb_listener_arn` | reported in `missing` |
| IAM provider the role is registered in | `environment` | `iam_provider_id` | created with the environment's dimensions; when given, only the `lambda` entry is added |
| Scope-configuration values | `environment` | `scope_configuration_id` | written for the environment's dimensions, once the account's image is known |
| Agent channel | `environment` | `channel_id`, `create_channel` | created, selecting the agent by `agent_tags` and routing only the environment's dimensions |

The organization's state is the memory: ownership, idempotency, upgrades
(`ref` moves) and removal (`destroy`) are OpenTofu's. The modules still
report what they touched in their `resources` and `missing` outputs, marked
`owned` or `provided`, for whoever wants to show it.

## Without a Terraform repository: the runner

`run/` is a root that configures the providers from the environment and calls
the three modules: `installation` once, `account` once (one AWS provider, so
one account) and `environment` once per dimension set. Installing a second
account is a second run, with its own `NP_INSTALL_STATE` and the first run's
`scope_type_id` and `scope_configuration_specification_id` in `parameters`.
Its entrypoints (`install`, `update`, `uninstall`, `status`) take:

- `NP_INSTALL_CONTEXT`: JSON with `installation` (`id`, `nrn`, `package_slug`,
  `version`), `agent` (`role_arn`, `tags`) and `parameters`: `account` (what
  the account already has) and `environments` (one entry per dimension set,
  with what each already has on the platform). Data only, never a secret.
- `NP_INSTALL_STATE`: path of the state file the runner keeps between runs.

Credentials come from the environment, the way the worker already gets them:
`NULLPLATFORM_API_KEY` (the agent's `NP_API_KEY` is bridged to it) and the
runner's AWS credentials. `NULLPLATFORM_HOST` points at another API host.
`np`, `aws`, `jq`, `curl` and `tofu` are required; the worker image ships
them.

`run/lib/context` is what makes the runner different from the modules: when
`parameters` leaves something out, it resolves it through the API and ECR
(the specification by the package slug, an existing scope type and schema;
the environments from the cloud providers visible from the NRN; for the
account the role an environment's IAM provider already lists under `lambda`,
the bucket and placeholder an existing scope-configuration names, the
placeholder in ECR, the ALB listener in a networking provider; per
environment its IAM provider, scope-configuration and channel), and it keeps
what the previous report marked as owned out of discovery, so a second run
reconciles instead of adopting its own resources. An organization with its
own Terraform never runs it.

Each entrypoint prints the installation's report on stdout:

```json
{ "outputs":   { "scope_type_id": "…", "role_arn": "arn:…", "state_bucket": "…", "channel_id": { "development": "…", "staging": "…" }, … },
  "resources": [ { "type": "scope_type", "id": "…", "ownership": "owned" }, { "type": "aws_iam_role", "id": "arn:…", "account": "default", "ownership": "owned" },
                 { "type": "provider_config", "id": "…", "environment": "staging", "ownership": "provided" }, … ],
  "missing":   [ { "need": "alb_listener", "account": "default", "hint": "optional: …" } ] }
```

## What is emulated until the platform has it

- **IAM provider entries.** The API updates a provider as a whole, so adding one
  entry to an existing IAM provider is done by `environment/scripts/iam_role_entry`
  (read, merge, write). An entry endpoint and a `nullplatform_iam_role_entry`
  resource would replace it at that seam.
- **NRN settings** are written by `np nrn patch` from `scripts/nrn_settings`,
  as `scope_definition` does; the patch merges keys.
- **Discovery** in the runner, because the Terraform provider has no data source
  for provider configs, scope types or channels. With them, the modules could
  look things up themselves and the runner would lose most of `lib/context`.

## Not provisioned here, on purpose

- **The placeholder image** needs docker buildx (`scope/placeholder/publish`).
  The repository is created and the image reported in `missing`, with the
  command. Publishing it from CI to a public registry and copying it here would
  close the gap.
- **The public ALB** with its certificate and DNS stays in the organization's
  infrastructure (`specs/requirements` can create it). Without it, scopes get
  no HTTP endpoint through an ALB and the installation says so.

## Known tightening point

`account/policies/` are the four policies `specs/requirements` ships today, kept
identical so the role created here behaves like the one organizations already
run. `lambda-iam.json` lets the worker create and change execution roles under
`nullplatform-*` and `np-lambda-*`, a pattern the created role's own name
falls under, so the worker could in principle widen its own role. Scoping IAM
writes to `np-lambda-*`, requiring a permissions boundary on `CreateRole` and
`PutRolePolicy`, and conditioning `PassRole` on `lambda.amazonaws.com` is the
right next step, but it changes what the scope workflows may do and belongs to
the requirements module and the workflows together, not to this folder alone.
