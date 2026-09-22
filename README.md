# AWS Lambda Deployment Scope

This scope provides infrastructure-as-code for deploying and managing serverless functions on **AWS Lambda**. It uses a **modular Terraform architecture** with layered setup scripts that compose provider, IAM, compute, networking, and DNS modules into a complete deployment pipeline.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Scope Structure](#scope-structure)
- [Features](#features)
- [Service Specification](#service-specification)
- [Configuration](#configuration)
- [Deployment Strategies](#deployment-strategies)
- [Diagnostics](#diagnostics)
- [Setup Script Patterns](#setup-script-patterns)
- [Run Locally as a Package](#run-locally-as-a-package)
- [Testing](#testing)
- [Quick Reference](#quick-reference)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        WORKFLOW ENGINE                           │
│  (workflows/initial.yaml, blue_green.yaml, delete.yaml, ...)   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      MODULE COMPOSITION                          │
│                                                                  │
│  ┌──────────┐ ┌─────┐ ┌─────────┐ ┌────────────┐ ┌──────────┐ │
│  │ PROVIDER │→│ IAM │→│ COMPUTE │→│ NETWORKING │→│   DNS    │ │
│  │  (aws)   │ │     │ │(lambda) │ │(apigw/alb) │ │(route53) │ │
│  └──────────┘ └─────┘ └─────────┘ └────────────┘ └──────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     TERRAFORM / OPENTOFU                         │
│  (composed modules from all active layers)                      │
└─────────────────────────────────────────────────────────────────┘
```

### Module Flow

1. **Provider**: Configures AWS credentials, region, and Terraform state backend
2. **IAM**: Creates/updates Lambda execution role with required policies
3. **Compute (Lambda)**: Deploys function code, versions, aliases, and concurrency settings
4. **Networking**: Sets up API Gateway (public) or ALB target group (private)
5. **DNS (Route53)**: Creates DNS records pointing to the networking endpoint

---

## Scope Structure

```
lambda/
├── specs/                              # Platform definitions
│   ├── service-spec.json.tpl           # Developer-facing capabilities
│   ├── scope-type-definition.json.tpl  # Scope type metadata
│   ├── notification-channel.json.tpl   # Event notification channel
│   └── actions/                        # Action definitions (14 actions)
│       ├── create-scope.json.tpl
│       ├── update-scope.json.tpl
│       ├── delete-scope.json.tpl
│       ├── diagnose-scope.json.tpl
│       ├── adjust-provisioned-concurrency.json.tpl
│       ├── adjust-reserved-concurrency.json.tpl
│       ├── invoke.json.tpl
│       ├── start-initial.json.tpl
│       ├── start-blue-green.json.tpl
│       ├── switch-traffic.json.tpl
│       ├── finalize-blue-green.json.tpl
│       ├── delete-deployment.json.tpl
│       ├── diagnose-deployment.json.tpl
│       └── rollback-deployment.json.tpl
├── values.yaml                         # DevOps configuration with defaults
│
├── scope/                              # Scope lifecycle operations
│   ├── build_context
│   ├── scripts/
│   │   ├── create_iam_role
│   │   ├── create_placeholder_lambda
│   │   ├── delete_lambda
│   │   ├── delete_iam_role
│   │   ├── generate_domain
│   │   ├── invoke_lambda
│   │   ├── store_scope_metadata
│   │   ├── update_iam_role
│   │   ├── adjust_provisioned_concurrency
│   │   └── adjust_reserved_concurrency
│   └── workflows/
│       ├── create.yaml
│       ├── update.yaml
│       ├── delete.yaml
│       ├── diagnose.yaml
│       ├── invoke.yaml
│       ├── adjust_provisioned_concurrency.yaml
│       └── adjust_reserved_concurrency.yaml
│
├── deployment/                         # Deployment operations (Terraform)
│   ├── build_context
│   ├── compose_modules
│   ├── do_tofu
│   ├── scripts/
│   │   ├── cleanup_new_version
│   │   ├── cleanup_old_version
│   │   ├── merge_iam_policies
│   │   ├── rollback_alias
│   │   ├── store_nrn_metadata
│   │   ├── sync_parameters_to_secrets_manager
│   │   ├── update_alias_full
│   │   ├── update_alias_weights
│   │   └── wait_provisioned_concurrency
│   ├── workflows/
│   │   ├── initial.yaml
│   │   ├── blue_green.yaml
│   │   ├── switch_traffic.yaml
│   │   ├── finalize.yaml
│   │   ├── delete.yaml
│   │   └── rollback.yaml
│   ├── provider/aws/                   # AWS provider config
│   │   ├── setup
│   │   └── modules/
│   ├── iam/                            # IAM role/policy management
│   │   ├── setup
│   │   └── modules/
│   ├── compute/lambda/                 # Lambda function config
│   │   ├── setup
│   │   └── modules/
│   ├── networking/                     # Access layer
│   │   ├── api_gateway/               # Public access
│   │   │   ├── setup
│   │   │   └── modules/
│   │   └── alb/                       # Private access
│   │       ├── setup
│   │       └── modules/
│   └── dns/route53/                    # DNS records
│       ├── setup
│       └── modules/
│
├── diagnose/                           # Health checks
│   ├── build_context
│   ├── notify_check_running
│   ├── notify_results
│   └── checks/
│       ├── lambda_exists
│       ├── lambda_active
│       ├── iam_role_valid
│       ├── dns_resolves
│       ├── networking_healthy
│       └── provisioned_concurrency
│
├── instance/                           # Execution listing
│   ├── build_context
│   ├── list_instances
│   └── workflows/
│       └── list.yaml
│
├── log/                                # CloudWatch logs
│   ├── build_context
│   ├── fetch_logs
│   └── workflows/
│       └── log.yaml
│
├── metric/                             # CloudWatch metrics
│   ├── build_context
│   ├── fetch_metric
│   ├── list_metrics
│   └── workflows/
│       ├── metric.yaml
│       └── list.yaml
│
├── tests/                              # BATS unit tests
│   ├── scripts/
│   │   ├── build_context.bats
│   │   ├── scope_build_context.bats
│   │   ├── create_iam_role.bats
│   │   ├── ...
│   │   └── helpers/
│   │       ├── test_helper.bash
│   │       └── mock_context.bash
│
└── utils/
    └── get_config_value                # Config value resolution utility
```

---

## Features

### Deployment (Required)
Manages Lambda function deployments with multiple strategies: initial, blue-green, traffic switching, rollback, and finalization.

### Scope (Required)
Handles scope lifecycle: creates IAM roles, placeholder functions, generates domains, and stores metadata.

### Instance
Lists Lambda function executions and invocation history.

### Log
Retrieves application logs from CloudWatch with configurable retention (default: 30 days).

### Metric
Fetches and lists CloudWatch metrics for Lambda functions (invocations, duration, errors, throttles, etc.).

### Diagnose
Runs 6 health checks with structured reporting:

| Check | What It Validates |
|-------|-------------------|
| `lambda_exists` | Function exists in AWS |
| `lambda_active` | Function is accessible and responding |
| `iam_role_valid` | IAM role exists with required permissions |
| `dns_resolves` | Domain name resolves correctly |
| `networking_healthy` | API Gateway or ALB responds to health checks |
| `provisioned_concurrency` | Provisioned concurrency is ready (if enabled) |

### Concurrency Management
Dedicated actions to adjust reserved and provisioned concurrency without redeployment.

### Function Invocation
Direct Lambda invocation with custom JSON payloads for testing.

---

## Service Specification

The `service-spec.json.tpl` defines the developer-facing capabilities:

| Capability | Options | Default |
|------------|---------|---------|
| **Runtime** | Node.js 24/22/20, Python 3.14/3.13/3.12/3.11/3.10, Java 25/21/17/11, .NET 10/8, Ruby 4.0/3.4/3.3, Custom (AL2023/AL2) | `nodejs22.x` |
| **Memory** | 128 MB - 10 GB | `256 MB` |
| **Timeout** | 3 - 900 seconds | `30` |
| **Architecture** | ARM64 (Graviton2), x86_64 | `arm64` |
| **Visibility** | Public (API Gateway), Private (ALB) | — |
| **Package Type** | Zip, Docker Image | — |
| **Reserved Concurrency** | Unreserved, Custom value | `unreserved` |
| **Provisioned Concurrency** | Unprovisioned, Custom value | `unprovisioned` |
| **VPC** | Optional private networking | Disabled |
| **Layers** | Custom Lambda layers (ARN-based) | None |
| **Dead Letter Queue** | SQS queue or SNS topic ARN for failed async invocations | None |
| **Continuous Delivery** | Git branch-based auto-deployment | — |

### Event-driven scopes

A function triggered by something other than its own API Gateway or ALB needs
an invoke permission (see [External invocation](#external-invocation)) and a way
for the trigger to find it.

`create-scope` and `update-scope` publish the function's identity to the scope's
NRN, so an event source mapping can target the `main` alias without re-deriving
names. Scopes created earlier are backfilled on the next `update-scope`.

| NRN key | Value |
|---------|-------|
| `lambda.function_name` | Function name |
| `lambda.function_arn` | Unqualified function ARN |
| `lambda.alias_arn` | `main` alias ARN — the event source mapping target |
| `lambda.main_alias` | Alias name (`main`) |
| `lambda.execution_role_arn` / `lambda.execution_role_name` | Execution role |

---

## Configuration

### values.yaml

Key configuration values with their defaults:

```yaml
# Domain
DOMAIN: "nullapps.io"
USE_ACCOUNT_SLUG: true

# Lambda Defaults
DEFAULT_RUNTIME: "nodejs20.x"
DEFAULT_HANDLER: "index.handler"
DEFAULT_MEMORY: 256
DEFAULT_TIMEOUT: 30
DEFAULT_ARCHITECTURE: "arm64"
DEFAULT_EPHEMERAL_STORAGE: 512

# Nullplatform Agent
USE_NULL_AGENT: true

# Deployment Timeouts
DEPLOYMENT_MAX_WAIT_IN_SECONDS: 600
PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS: 600

# API Gateway (Public)
API_GATEWAY_STAGE_NAME: "main"
API_GATEWAY_THROTTLING_BURST_LIMIT: 5000
API_GATEWAY_THROTTLING_RATE_LIMIT: 10000

# ALB (Private)
ALB_LISTENER_RULE_CAPACITY: 100
ALB_LISTENER_RULE_ALERT_THRESHOLD: 80

# CloudWatch
LOG_RETENTION_DAYS: 30

# Parameters Strategy
PARAMETERS_STRATEGY: "env"              # or "secretsmanager"
```

### Placeholder Image (Scope Bootstrap)

When a scope is created, the Lambda function and its IAM role must exist **before**
the first real deployment — otherwise aliases, networking, and IAM have nothing to
attach to. To bootstrap this, `create-scope` provisions a throwaway **placeholder**
function that the first deployment then overwrites with the real code.

How the placeholder is sourced depends on the scope's **package type**:

- **Zip** — fully self-contained. A minimal handler ships pre-built and
  base64-encoded in the repo (`scope/placeholder/placeholder_lambda.zip.b64`) and is
  used automatically. **No configuration needed.**
- **Image** — the placeholder must be a container image, and this is where
  `PLACEHOLDER_IMAGE_URI_DEFAULT` comes in.

#### Why `PLACEHOLDER_IMAGE_URI_DEFAULT` is needed for Image scopes

A Lambda function with `PackageType=Image` can only pull from a **private ECR
repository in the same account and region** — Lambda rejects `public.ecr.aws`
images at function-creation time. The built-in default in
`scope/scripts/resolve_placeholder_image` points at a public image
(`public.ecr.aws/nullplatform/aws-lambda/nullplatform-lambda-placeholder:latest`),
which is fine to *validate* but cannot actually back a real Lambda function.

So for Image-based scopes you **must** mirror a placeholder into your own private
ECR and point the scope at it. The image must also be **single-arch matching the
scope architecture** (`-amd64` for `x86_64`, `-arm64` for `arm64`) — Lambda does
not accept multi-arch manifest lists.

#### Resolution precedence

The placeholder image URI is resolved in this order (first match wins):

1. scope-configurations provider key `deployment.placeholder_image_uri` — per-scope,
   managed without code
2. `PLACEHOLDER_IMAGE_URI_DEFAULT` env var — the **account-wide** knob, set in
   `values.yaml` or via the agent's `extra_envs` (Helm)
3. the public default in `scope/scripts/resolve_placeholder_image` (validation-only
   fallback; not usable for real Image functions)

Because the URI is account-specific, `values.yaml` ships it commented out — set it
once per installation and every Image scope in that account uses it, unless a
specific scope overrides it via the provider key.

#### Publishing a placeholder image

Use the helper script to build and push the single-arch placeholders to your private
ECR (it creates the repository if it does not exist):

```bash
export PLACEHOLDER_IMAGE_REPO=123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder
lambda/scope/placeholder/publish        # pushes <repo>:latest-arm64 and <repo>:latest-amd64
```

Then set the URI (matching your scope architecture) in `values.yaml` or the agent's
`extra_envs`:

```yaml
PLACEHOLDER_IMAGE_URI_DEFAULT: "123456789012.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest-arm64"
```

### External invocation

Set in the **scope-configuration** provider (`triggers.invoke_permissions`) — a
privilege grant belongs to whoever operates the account, not to the scope form.
Dimensions are allowed, so it can differ per environment.

```json
{
  "triggers": {
    "invoke_permissions": [
      {
        "statement_id": "eventbridge-daily",
        "principal": "events.amazonaws.com",
        "source_arn": "arn:aws:events:us-east-1:111122223333:rule/daily-report",
        "scope": "my-scope"
      }
    ]
  }
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `statement_id` | yes | `[a-zA-Z0-9_-]` only. Stored as `np-ext-<statement_id>`. |
| `principal` | yes | AWS service principal. |
| `source_arn` | recommended | Without it, *any* resource of that service in the account can invoke the function. |
| `source_account` | no | Required for S3, whose bucket ARNs carry no account ID. |
| `action` | no | Defaults to `lambda:InvokeFunction`. |
| `scope` | recommended | Scope slug or id. The provider resolves against the scope's NRN, so a value set higher up applies to every Lambda scope beneath it. |

Reconciled idempotently on `create-scope` and `update-scope`. Only `np-ext-`
statements are ever deleted, so `AllowAPIGatewayInvoke`, `AllowALBInvoke` and
anything added out of band survive.

### Dead letter queue

`dead_letter_target_arn` (a scope attribute) is the SQS queue or SNS topic that
receives events whose **asynchronous** invocation failed after all retries — not
the redrive policy of a queue the function consumes from.

Setting it enables `DeadLetterConfig` and grants the execution role
`sqs:SendMessage` or `sns:Publish` on that ARN alone; without the grant Lambda
drops the event silently. Clearing it reverts both. A target encrypted with a
customer-managed KMS key also needs `kms:GenerateDataKey` (plus `kms:Decrypt`
for SQS) on the key, which the scope cannot derive — add it yourself.

> **Why these two are not in Terraform.** The scope's tofu state holds the
> *placeholder* function while deployments mutate the real one via the AWS CLI,
> so an `apply` on update would roll the function back. Both are reconciled by
> AWS CLI scripts instead, touching only the field they own.

### What `update-scope` reconciles

| Reconciled by `update-scope` | Applied on the next deployment |
|------------------------------|--------------------------------|
| `vpc_enabled` (execution role policy) | `memory`, `timeout`, `ephemeral_storage` |
| `triggers.invoke_permissions` | `runtime`, `handler` (Zip only) |
| `dead_letter_target_arn` | `layers`, environment variables, VPC config |
| NRN identity metadata | |

`reserved_concurrency` and `provisioned_concurrency` have their own actions.

### Resource Naming

| Resource | Format | Example |
|----------|--------|---------|
| Lambda Function | `{scope_id}-{application}-{scope}` (max 64 chars) | `12345abcdef-webapp-api` |
| Terraform State | `lambda/{scope_id}/terraform.tfstate` | — |
| Alias (primary) | `main` | — |
| Alias (warmup) | `warmup` | — |

### Resource Tags

All AWS resources are tagged with:
```json
{
  "nullplatform:scope-id": "{scope_id}",
  "nullplatform:deployment-id": "{deployment_id}",
  "nullplatform:namespace": "{namespace_slug}",
  "nullplatform:application": "{application_slug}",
  "nullplatform:scope": "{scope_slug}"
}
```

---

## Deployment Strategies

### Initial Deployment

Full infrastructure setup on first deployment:

```
build_context → sync_parameters → setup_provider → setup_iam → setup_compute
→ setup_networking (api_gateway | alb) → setup_dns → compose_modules
→ tofu apply → wait_provisioned_concurrency → store_metadata
```

### Blue-Green Deployment

Canary deployment with weighted traffic shifting:

1. Deploys new version using the initial workflow (skipping full traffic switch)
2. Traffic is split between old and new versions via alias weights
3. Gradual traffic migration: `switch_traffic` action with desired percentage
4. Finalization: `finalize` moves 100% traffic and cleans up old version

### Rollback

Automatic recovery on deployment failure:

```
build_context → restore_alias → rollback_iam → cleanup_new_version
```

### Traffic Switching

Supports both gradual and immediate traffic migration between Lambda versions using weighted alias routing.

---

## Diagnostics

The diagnose workflow uses the executor pattern with before/after hooks for structured reporting:

```yaml
steps:
  - name: diagnose
    type: executor
    before_each:
      name: notify_check_running
      type: script
      file: "$SERVICE_PATH/diagnose/notify_check_running"
    after_each:
      name: notify_check_results
      type: script
      file: "$SERVICE_PATH/diagnose/notify_results"
    folders:
      - "$SERVICE_PATH/diagnose/checks"
```

Each check in `diagnose/checks/` runs independently, and results are reported to the nullplatform notification system.

---

## Setup Script Patterns

Each Terraform module layer has a `setup` script that:

1. **Validates** required environment variables and context
2. **Fetches** external data if needed (AWS APIs, nullplatform API)
3. **Updates** `TOFU_VARIABLES` with module-specific configuration
4. **Registers** the module directory in `MODULES_TO_USE`

### Example: Compute Setup

```bash
#!/bin/bash
set -euo pipefail

echo "  Validating Lambda configuration..."

# Validate required variables
if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
  echo "   LAMBDA_FUNCTION_NAME is missing"
  exit 1
fi

# Update TOFU_VARIABLES
TOFU_VARIABLES=$(echo "$TOFU_VARIABLES" | jq \
  --arg function_name "$LAMBDA_FUNCTION_NAME" \
  '. + { lambda_function_name: $function_name }')

# Register module
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_TO_USE="$MODULES_TO_USE,${script_dir}/modules"
```

---

## Run Locally as a Package

You can run this scope on your machine the way production runs it: a dockerized
nullplatform agent registers with the platform, spawns this scope's worker
container, and hands it each action over gRPC. The bash scripts are not changed
for this. The worker image is built `FROM` the `worker-bridge` base (see the
`Dockerfile`), which receives the action and runs `lambda/entrypoint` exactly as
the classic agent did.

This repo is a **base package**: it has no `package.json` and no manifest. The
two tasks in `.mise.toml` are the whole contract with the CLI.

| Command | Runs | Does |
|---------|------|------|
| `np package build --image` | `mise run build:image` | Builds `scopes-lambda-worker:dev` |
| `np package run` | `mise run run` | Builds the image, then starts the local agent |

### Prerequisites

- **Docker**, with host networking. On Linux it works as is; on Docker Desktop
  enable *host networking* in the settings.
- **[mise](https://mise.jdx.dev)**. Run `mise trust` once in this directory.
- **`NP_API_KEY`**: an API key the agent registers with.
- **`np` with the `package` commands.** They are in review in
  [nullplatform/cli#243](https://github.com/nullplatform/cli/pull/243). Until
  that ships you lose nothing but environment forwarding: `mise run run` starts
  the same agent.

### Run it

```bash
export NP_API_KEY=...

np package run --log-level DEBUG     # Ctrl+C to stop
# or, without the CLI:
mise run run
```

The agent is tagged `package:scopes-lambda` and `local:<your user>`. It receives
an action only when the scope's notification channel selects those tags, so
point a channel at `local:<your user>` to route work to your machine.

> **Tags decide who gets the work.** Never start a local agent with tags a
> production channel selects: it would receive production actions.

### Settings

| Variable | Default | Purpose |
|----------|---------|---------|
| `NP_API_KEY` | required | The key the agent registers with. `np package run --api-key` also sets it. |
| `NP_LOG_LEVEL` | `INFO` | Agent log level. `np package run --log-level` also sets it. |
| `NP_PACKAGE_SLUG` | `scopes-lambda` | The slug in the `package:<slug>` tag. Set it when your package is published under another slug. |
| `NP_LOCAL_USER` | `$USER` | The value of the `local:<user>` tag. `np package run` sets it. |
| `NP_AGENT_IMAGE` | `controlplane-agent:alpha-packages-2.2.0` | The agent image to run. |
| `NP_PACKAGE_ENV_FLAGS` | empty | Set by `np package run`: the shell variables to forward, as `-e NAME` flags. |

### AWS credentials and your environment

`np package run` forwards your shell's environment to the agent container. It
holds back variables that describe your machine rather than the work: `PATH`,
`HOME`, `DOCKER_*`, `KUBECONFIG`, and the AWS variables that point at files the
container does not have (`AWS_PROFILE`, `AWS_CONFIG_FILE`,
`AWS_SHARED_CREDENTIALS_FILE`). So export credentials as variables:

```bash
eval "$(aws configure export-credentials --format env)"
np package run
```

Pass `--no-forward-env` to forward nothing. Every secret in your shell is
forwarded otherwise, and is readable with `docker inspect` on your machine.

> **Known limitation.** The variables reach the **agent** container, not the
> **worker** container the agent spawns. The agent's docker worker backend
> forwards only its own variables (`NP_API_KEY`, `NP_API_URL`, the gRPC and TLS
> settings); only its Kubernetes backend applies `NP_WORKER_ENV`. This scope's
> first step is `assume_role`, which needs AWS credentials **inside the worker**,
> so today a local run registers and receives actions but its AWS calls fail.
> This needs a change in `controlplane-agent`, not in this repo.

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| `set NP_API_KEY` | No API key in the environment | `export NP_API_KEY=...`, or pass `--api-key` |
| "doesn't look like a package" | An `np` build without base package support | Use a build that includes [cli#243](https://github.com/nullplatform/cli/pull/243), or run `mise run run` |
| `mise` refuses to run the tasks | The config is not trusted yet | `mise trust` |
| The agent starts but never reaches the worker | No host networking | Enable host networking in Docker Desktop |
| The agent is up but no action arrives | No channel selects your tags | Add a channel selector for `local:<your user>` |

---

## Testing

This module uses the testing framework defined in the [scope-testing](https://github.com/nullplatform/scope-testing) repository, which is included as a Git submodule. To initialize the submodule, run:

```bash
git submodule add git@github.com:nullplatform/scope-testing.git testing
git submodule init && git submodule update
```

We use **three types of tests** to ensure quality at different levels:

| Test Type | What it Tests | Location | Command |
|-----------|---------------|----------|---------|
| **Unit Tests (BATS)** | Bash scripts (build_context, scope scripts, deployment scripts) | `lambda/scope/tests/scripts/`, `lambda/deployment/tests/scripts/` | `make test-unit` |
| **Tofu Tests** | Terraform modules (IAM, Lambda, API Gateway, ALB, Route53) | `lambda/scope/tofu/*/modules/*.tftest.hcl` | `make test-tofu` |

### Unit Tests (BATS)

Test bash scripts in isolation using mocked AWS CLI and nullplatform API commands.

**Example test files:**
- `scope/tests/scripts/scope_build_context.bats` - Scope context extraction
- `scope/tests/scripts/sync_invoke_permissions.bats` - External invoke permission reconciliation
- `deployment/tests/scripts/update_alias_weights.bats` - Traffic splitting logic

Two mocking styles live in `scope/tests/scripts/helpers/`:

- `test_helper.bash` — a sequential queue that answers every AWS call in order.
  Fine for a script that makes one or two calls.
- `aws_cli_mock.bash` — keys responses by `<service> <subcommand>` and records
  every invocation. Use it for scripts that branch on what AWS returns, and to
  assert on calls that must *not* happen.

**Scripts that use `return` instead of `exit`** — the workflow engine sources
them — must be tested with `run bash -c "source '<script>'"`. Running them with
`run bash <script>` makes `return` a warning that does not stop the script, so
every failure assertion silently passes.

### Tofu Tests (OpenTofu)

Test Terraform modules using `tofu test` with mock providers.

**Example test files:**
- `scope/tofu/iam/modules/iam.tftest.hcl`
- `scope/tofu/compute/lambda/modules/lambda.tftest.hcl`
- `scope/tofu/networking/api_gateway/modules/api_gateway.tftest.hcl`
- `scope/tofu/networking/alb/modules/alb.tftest.hcl`
- `scope/tofu/dns/route53/modules/route53.tftest.hcl`

### Running Tests

```bash
# Run all tests
make test-all

# Run specific test types
make test-unit                         # BATS unit tests
make test-tofu                         # OpenTofu module tests

# Run tests for this module only
make test-unit MODULE=lambda
make test-tofu MODULE=lambda

# The make targets shell out to ./testing/, which is not committed. Until the
# submodule is added, run a suite directly:
bats lambda/scope/tests/scripts/*.bats
```

---

## Quick Reference

### Environment Variables (Provider)

```bash
export TOFU_PROVIDER=aws
export AWS_REGION=us-east-1
export TOFU_PROVIDER_BUCKET=my-state-bucket
export TOFU_LOCK_TABLE=my-lock-table
```

### Actions Reference

| Action | Type | Parameters |
|--------|------|------------|
| `create-scope` | Scope | scope_id |
| `update-scope` | Scope | scope_id |
| `delete-scope` | Scope | scope_id |
| `diagnose-scope` | Scope | scope_id |
| `invoke` | Scope | scope_id, payload (optional) |
| `adjust-provisioned-concurrency` | Scope | scope_id, value |
| `adjust-reserved-concurrency` | Scope | scope_id, value |
| `start-initial` | Deployment | scope_id, deployment_id |
| `start-blue-green` | Deployment | scope_id, deployment_id |
| `switch-traffic` | Deployment | scope_id, deployment_id, desired_traffic |
| `finalize-blue-green` | Deployment | scope_id, deployment_id |
| `rollback-deployment` | Deployment | scope_id, deployment_id |
| `delete-deployment` | Deployment | scope_id, deployment_id |
| `diagnose-deployment` | Deployment | scope_id, deployment_id |

### Visibility Modes

| Mode | Networking | Use Case |
|------|------------|----------|
| **Public** | API Gateway + Route53 | Internet-facing APIs and webhooks |
| **Private** | ALB + Route53 | Internal microservices and backend functions |

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "Function name too long" | Name exceeds 64 chars | Shorten namespace/application/scope slugs |
| "Placeholder image not found" | Image scope with no private placeholder published | Run `lambda/scope/placeholder/publish` and set `PLACEHOLDER_IMAGE_URI_DEFAULT` (see [Placeholder Image](#placeholder-image-scope-bootstrap)) |
| "Provisioned concurrency timeout" | Warmup taking too long | Increase `PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS` |
| "ALB listener rule capacity" | Too many rules on ALB | Increase `ALB_LISTENER_RULE_CAPACITY` in values.yaml |
| "Module not composed" | `MODULES_TO_USE` not updated | Verify setup script appends to `MODULES_TO_USE` |
| "Backend not configured" | Missing provider setup | Ensure provider setup runs before other modules |
