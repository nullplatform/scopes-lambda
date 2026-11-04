# Installation

Everything this scope needs installed in an organization, in one place, written
by the package and run by the platform. It crosses the layers on purpose: the AWS
provider and the nullplatform provider live in the same root module, because an
installation is exactly a change that touches the cloud account and the platform
at once.

Each requirement is **received as a parameter**, **found and adopted**, or
**provisioned here**:

| Requirement | Parameter | When absent |
|---|---|---|
| Targets (one per cloud provider the NRN resolves, with its dimensions) | `targets` | discovered: the `aws-configuration` providers visible from the NRN |
| Role the worker assumes | `targets.<key>.role_arn` | the IAM provider's `lambda` entry if it has one (adopted); else created, trusting the agent role |
| IAM provider the role is registered in | `targets.<key>.iam_provider_id` | discovered for the dimensions; created when there is none |
| OpenTofu state bucket | `targets.<key>.state_bucket` | an existing scope-configuration's value; else created |
| Placeholder image | `targets.<key>.placeholder_image_uri` | an existing scope-configuration's value, or the image in ECR; **never built here**: the repository is created and the image reported in `missing` |
| Public ALB listener (optional) | `targets.<key>.alb_listener_arn` | the networking provider's `load_balancer.public.listener_arn`; else reported in `missing` |
| Scope-configuration values per target | `targets.<key>.scope_configuration_id` | discovered for the dimensions (adopted); else written with the values above, once the image is known |
| Scope-configuration schema | `scope_configuration_slug` (default `aws-lambda`) | adopted when visible, the copy's for instance; else created from `specs/scope-configuration.json.tpl` |
| Scope type | `scope_type_name`, `scope_type_description` | adopted when one already points at the specification; else created |
| NRN settings (metrics and logs providers) | `metrics_provider`, `log_provider` | written with the defaults |
| Agent channel | `create_channel` (default `true`) | adopted when one routes the package at the NRN; else created, selecting the agent by `agent.tags` |

What the installation **reads and never writes**: the cloud providers (account,
region) and the networking provider (ALB listener). What it **creates**, it
owns and `uninstall` removes. What it **finds**, it adopts: an existing IAM
provider only gets this package's entry (and loses it on uninstall); an
existing schema, scope type, scope-configuration, channel or role is reused and
left alone.

## Contract with the runner

The entrypoints (`install`, `update`, `uninstall`, `status`) take two environment
variables, the ones `np package install` and the agent will set:

- `NP_INSTALL_CONTEXT`: JSON with `installation` (`id`, `nrn`, `package_slug`,
  `version`), `agent` (`role_arn`, `tags`), `parameters` and
  `credentials.platform.api_key`.
- `NP_INSTALL_STATE`: path of the state file. The runner hands over the previous
  one and keeps the updated one; this module never needs a bucket of its own.

AWS credentials are the runner's: a profile when run locally, the agent's role
when run by the agent. `np`, `aws`, `jq`, `curl` and `tofu` are required; the
worker image ships them.

Each entrypoint prints one JSON document on stdout, the installation's report:

```json
{ "outputs":   { "role_arn": { "default": "arn:…" }, "state_bucket": { "default": "…" }, "placeholder_image_uri": { "default": "…" },
                 "scope_type_id": "…", "scope_configuration_specification": "…", "channel_id": "…" },
  "resources": [ { "type": "scope_type", "id": "…", "ownership": "adopted" }, … ],
  "missing":   [ { "need": "alb_listener", "target": "default", "hint": "optional: …" } ] }
```

`ownership` is `owned` (created here, removed on uninstall), `provided` (a
parameter) or `adopted` (found and reused, never removed). Logs go to stderr.

## What is emulated until the platform has it

- **IAM provider entries.** The API updates a provider as a whole, so adding one
  entry to an IAM provider the organization already owns is done by
  `scripts/iam_role_entry` (read, merge, write). The right shape is an entry
  endpoint and a `nullplatform_iam_role_entry` resource that owns only its entry.
- **NRN settings** are written by `np nrn patch` from `scripts/nrn_settings`,
  as `scope_definition` does; the patch merges keys.
- **Discovery.** The Terraform provider has no data source for provider configs,
  scope types or channels, so `lib/context` resolves them through the API (and
  the placeholder through ECR) before OpenTofu runs, walking up the NRN the way
  the platform does.
- **The agent's role and tags** come in the context; the platform knows them.

## Not provisioned here, on purpose

- **The placeholder image** needs docker buildx (`scope/placeholder/publish`).
  The repository is created and the image reported in `missing`, with the
  command. Publishing it from CI to a public registry and copying it here would
  close the gap.
- **The public ALB** with its certificate and DNS stays in the organization's
  infrastructure (`specs/requirements` can create it). Without it, scopes get
  no HTTP endpoint through an ALB and the installation says so.

## Known tightening point

`policies/` are the four policies `specs/requirements` ships today, kept
identical so the role created here behaves like the one organizations already
run. `lambda-iam.json` lets the worker create and change execution roles under
`nullplatform-*` and `np-lambda-*`, a pattern the created role's own name
falls under, so the worker could in principle widen its own role. Scoping IAM
writes to `np-lambda-*`, requiring a permissions boundary on `CreateRole` and
`PutRolePolicy`, and conditioning `PassRole` on `lambda.amazonaws.com` is the
right next step, but it changes what the scope workflows may do and belongs to
the requirements module and the workflows together, not to this folder alone.

## Layout

```
installation/
  install · update · uninstall · status   entrypoints (bash)
  lib/context                              NP_INSTALL_CONTEXT → tfvars, discovery
  scripts/iam_role_entry                   upsert/remove one entry of an IAM provider
  scripts/nrn_settings                     the two NRN settings, merged
  providers.tf · variables.tf · main.tf · outputs.tf
  policies/                                the role's four policies (unchanged; storage names the state bucket)
  tests/installation.tftest.hcl            plan-time tests with mocked providers
```
