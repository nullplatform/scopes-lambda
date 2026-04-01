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
| **Runtime** | Node.js 20/18, Python 3.12/3.11/3.10, Java 21/17/11, .NET 8/6, Ruby 3.3/3.2, Custom (AL2023/AL2) | `nodejs20.x` |
| **Memory** | 128 MB, 256 MB, 512 MB, 1 GB, 2 GB, 4 GB, 8 GB, 10 GB | `256 MB` |
| **Timeout** | 3 - 900 seconds | `30` |
| **Architecture** | ARM64 (Graviton2), x86_64 | `arm64` |
| **Visibility** | Public (API Gateway), Private (ALB) | — |
| **Package Type** | Zip, Docker Image | — |
| **Reserved Concurrency** | Unreserved, Custom value | `unreserved` |
| **Provisioned Concurrency** | Unprovisioned, Custom value | `unprovisioned` |
| **VPC** | Optional private networking | Disabled |
| **Layers** | Custom Lambda layers (ARN-based) | None |
| **Continuous Delivery** | Git branch-based auto-deployment | — |

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

### Resource Naming

| Resource | Format | Example |
|----------|--------|---------|
| Lambda Function | `{namespace}-{application}-{scope}-{scope_id}` (max 64 chars) | `acme-webapp-api-12345abcdef` |
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

## Testing

This module uses the testing framework defined in the [scope-testing](https://github.com/nullplatform/scope-testing) repository, which is included as a Git submodule. To initialize the submodule, run:

```bash
git submodule add git@github.com:nullplatform/scope-testing.git testing
git submodule init && git submodule update
```

We use **three types of tests** to ensure quality at different levels:

| Test Type | What it Tests | Location | Command |
|-----------|---------------|----------|---------|
| **Unit Tests (BATS)** | Bash scripts (build_context, scope scripts, deployment scripts) | `lambda/tests/scripts/` | `make -C testing test-unit` |
| **Tofu Tests** | Terraform modules (IAM, Lambda, API Gateway, ALB, Route53) | `lambda/deployment/*/modules/*.tftest.hcl` | `make -C testing test-tofu` |
| **Integration Tests** | Full workflow execution with mocked AWS | `lambda/tests/integration/` | `make -C testing test-integration` |

### Unit Tests (BATS)

Test bash scripts in isolation using mocked AWS CLI and nullplatform API commands.

**Example test files:**
- `tests/scripts/build_context.bats` - Deployment context extraction
- `tests/scripts/create_iam_role.bats` - IAM role creation
- `tests/scripts/update_alias_weights.bats` - Traffic splitting logic

### Tofu Tests (OpenTofu)

Test Terraform modules using `tofu test` with mock providers.

**Example test files:**
- `deployment/iam/modules/iam.tftest.hcl`
- `deployment/compute/lambda/modules/lambda.tftest.hcl`
- `deployment/networking/api_gateway/modules/api_gateway.tftest.hcl`
- `deployment/networking/alb/modules/alb.tftest.hcl`
- `deployment/dns/route53/modules/route53.tftest.hcl`

### Running Tests

```bash
# Run all tests
make -C testing test-all

# Run specific test types
make -C testing test-unit              # BATS unit tests
make -C testing test-tofu              # OpenTofu module tests
make -C testing test-integration       # Full workflow integration tests

# Run tests for this module only
make -C testing test-unit MODULE=lambda
make -C testing test-tofu MODULE=lambda
make -C testing test-integration MODULE=lambda

# Verbose output (integration only)
make -C testing test-integration VERBOSE=1
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
| "Provisioned concurrency timeout" | Warmup taking too long | Increase `PROVISIONED_CONCURRENCY_MAX_WAIT_SECONDS` |
| "ALB listener rule capacity" | Too many rules on ALB | Increase `ALB_LISTENER_RULE_CAPACITY` in values.yaml |
| "Module not composed" | `MODULES_TO_USE` not updated | Verify setup script appends to `MODULES_TO_USE` |
| "Backend not configured" | Missing provider setup | Ensure provider setup runs before other modules |
