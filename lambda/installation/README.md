# Installation

Everything this scope needs installed in an organization, written by the
package as OpenTofu modules the organization calls from its own Terraform, the
way it calls any vendor's module. It crosses the layers on purpose: the AWS
provider and the nullplatform provider live in the same modules, because an
installation is exactly a change that touches the cloud account and the
platform at once.

```
installation/            module, once per installation: scope type, scope-configuration schema, NRN settings
installation/target/     module, once per AWS account: role, state bucket, placeholder repository, IAM provider entry, scope-configuration values, agent channel
installation/run/        a runner root for installing without a Terraform repository (np package install, or by hand)
```

## From the organization's Terraform

One module call for the platform side, one per account with that account's
AWS provider. Nothing to copy from this repository, nothing in a bindings or
an infrastructure layer:

```hcl
provider "nullplatform" {}                     # NULLPLATFORM_API_KEY from the environment
provider "aws" { alias = "dev";  region = "us-east-1"; profile = "dev" }
provider "aws" { alias = "prod"; region = "us-east-1"; assume_role { role_arn = "arn:aws:iam::222222222222:role/platform-admin" } }

locals {
  lambda_installation = { id = nullplatform_package_installation.lambda.id, nrn = var.nrn, package_slug = "nullplatform-aws-lambda", version = "0.12.2" }
}

module "lambda" {
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation?ref=v0.12.2"
  installation             = local.lambda_installation
  service_specification_id = data.nullplatform_service_specification.lambda.id
  # scope_configuration_specification_id = "…"   reuse the copy's schema instead of creating one
}

module "lambda_dev" {
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/target?ref=v0.12.2"
  providers                = { aws = aws.dev }
  installation             = local.lambda_installation
  name                     = "development"
  dimensions               = { environment = "development" }
  agent_role_arn           = module.agent_dev.role_arn
  agent_tags               = { environment = "development" }      # this account's agent; the channel routes only development scopes to it
  service_specification_id = data.nullplatform_service_specification.lambda.id
  scope_configuration_slug = module.lambda.scope_configuration_slug
  placeholder_image_uri    = "111111111111.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
}

module "lambda_prod" {
  source                   = "git::https://github.com/nullplatform/scopes-lambda.git//lambda/installation/target?ref=v0.12.2"
  providers                = { aws = aws.prod }
  installation             = local.lambda_installation
  name                     = "production"
  dimensions               = { environment = "production" }
  agent_role_arn           = module.agent_prod.role_arn
  agent_tags               = { environment = "production" }
  service_specification_id = data.nullplatform_service_specification.lambda.id
  scope_configuration_slug = module.lambda.scope_configuration_slug
  role_arn                 = "arn:aws:iam::222222222222:role/their-lambda-role"   # bring your own
  state_bucket             = "their-lambda-tfstate"
  placeholder_image_uri    = "222222222222.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
  alb_listener_arn         = module.bindings.lambda_alb_listener_arn
}
```

Each requirement is **received as a parameter** or **provisioned here**:

| Requirement | Module | Parameter | When absent |
|---|---|---|---|
| Scope type | `installation` | `scope_type_id` | created with `scope_type_name` |
| Scope-configuration schema | `installation` | `scope_configuration_specification_id` | created from `specs/scope-configuration.json.tpl` |
| NRN settings (metrics and logs providers) | `installation` | `metrics_provider`, `log_provider` | written with the defaults |
| Agent channel, one per target because the agent is per account | `target` | `channel_id`, `create_channel` | created, selecting that account's agent by `agent_tags` and routing only the target's dimensions |
| Role the worker assumes | `target` | `role_arn` | created, trusting `agent_role_arn` |
| IAM provider the role is registered in | `target` | `iam_provider_id` | created with the target's dimensions; when given, only the `lambda` entry is added |
| State bucket | `target` | `state_bucket` | created |
| Placeholder image | `target` | `placeholder_image_uri` | **never built here**: the repository is created (or `placeholder_repository_url` reused) and the image reported in `missing` |
| ALB listener (optional) | `target` | `alb_listener_arn` | reported in `missing` |
| Scope-configuration values | `target` | `scope_configuration_id` | written for the target's dimensions, once the image is known |

The organization's state is the memory: ownership, idempotency, upgrades
(`ref` moves) and removal (`destroy`) are OpenTofu's. The modules still
report what they touched in their `resources` and `missing` outputs, marked
`owned` or `provided`, for whoever wants to show it.

## Without a Terraform repository: the runner

`run/` is a root that configures the providers from the environment and calls
the two modules for one account. Its entrypoints (`install`, `update`,
`uninstall`, `status`) take:

- `NP_INSTALL_CONTEXT`: JSON with `installation` (`id`, `nrn`, `package_slug`,
  `version`), `agent` (`role_arn`, `tags`) and `parameters`. Data only, never
  a secret.
- `NP_INSTALL_STATE`: path of the state file the runner keeps between runs.

Credentials come from the environment, the way the worker already gets them:
`NULLPLATFORM_API_KEY` (the agent's `NP_API_KEY` is bridged to it) and the
runner's AWS credentials. `NULLPLATFORM_HOST` points at another API host.
`np`, `aws`, `jq`, `curl` and `tofu` are required; the worker image ships
them.

`run/lib/context` is what makes the runner different from the modules: when
`parameters` leaves something out, it resolves it through the API and ECR
(the specification by the package slug, an existing scope type, schema and
channel, the targets from the cloud providers visible from the NRN, and per
target the IAM provider and its `lambda` entry, an existing scope-configuration
with its bucket and placeholder, the placeholder in ECR, the ALB listener in
the networking provider), and it keeps what the previous report marked as
owned out of discovery, so a second run reconciles instead of adopting its own
resources. An organization with its own Terraform never runs it.

Each entrypoint prints the installation's report on stdout:

```json
{ "outputs":   { "scope_type_id": "…", "channel_id": "…", "role_arn": { "default": "arn:…" }, "state_bucket": { "default": "…" }, … },
  "resources": [ { "type": "scope_type", "id": "…", "ownership": "owned" }, { "type": "provider_specification", "id": "…", "ownership": "provided" }, … ],
  "missing":   [ { "need": "alb_listener", "target": "default", "hint": "optional: …" } ] }
```

## What is emulated until the platform has it

- **IAM provider entries.** The API updates a provider as a whole, so adding one
  entry to an existing IAM provider is done by `target/scripts/iam_role_entry`
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

`target/policies/` are the four policies `specs/requirements` ships today, kept
identical so the role created here behaves like the one organizations already
run. `lambda-iam.json` lets the worker create and change execution roles under
`nullplatform-*` and `np-lambda-*`, a pattern the created role's own name
falls under, so the worker could in principle widen its own role. Scoping IAM
writes to `np-lambda-*`, requiring a permissions boundary on `CreateRole` and
`PutRolePolicy`, and conditioning `PassRole` on `lambda.amazonaws.com` is the
right next step, but it changes what the scope workflows may do and belongs to
the requirements module and the workflows together, not to this folder alone.
