# AWS Lambda Scope — Installation Guide

This guide walks through registering the AWS Lambda scope type in nullplatform using OpenTofu.

## Overview

The installation process creates:
- A **service specification** (the scope form developers fill in)
- A **scope type** (the runtime definition linking the spec to the agent)
- **Action specifications** (create-scope, start-initial, blue-green, etc.)
- A **notification channel** (connects nullplatform events to the agent)

## Prerequisites

See [prerequisites.md](./prerequisites.md) for agent setup, AWS permissions, and required repositories.

## Steps

### 1. Clone required repositories

```bash
git clone https://github.com/nullplatform/scopes-lambda /root/.np/nullplatform/scopes-lambda
git clone https://github.com/nullplatform/scopes-networking /root/.np/nullplatform/scopes-networking
git clone https://github.com/nullplatform/tofu-modules /root/.np/nullplatform/tofu-modules
```

> The paths above are the defaults used in `repo_path`. Adjust if you clone elsewhere.

### 2. Configure variables

```bash
cd install/tofu
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

| Variable | Required | Description |
|---|---|---|
| `nrn` | ✅ | Nullplatform Resource Name (`organization:account`) |
| `np_api_key` | ✅ | Nullplatform API key |
| `tags_selectors` | ✅ | Tags to select the agent (e.g. `{ environment = "production" }`) |
| `github_branch` | — | Branch to fetch specs from (default: `main`) |
| `repo_path` | — | Path where scopes-lambda is cloned on the agent |
| `overrides_enabled` | — | Set `true` to enable config overrides from scopes-networking |
| `overrides_repo_path` | — | Path to scopes-networking clone (e.g. `/root/.np/nullplatform/scopes-networking`) |
| `overrides_service_path` | — | Subfolder within overrides repo (e.g. `/lambda`) |

### 3. Initialize OpenTofu

```bash
tofu init \
  -backend-config="bucket=<your-state-bucket>" \
  -backend-config="region=<aws-region>"
```

### 4. Plan and apply

```bash
tofu plan
tofu apply
```

## Overrides

If this account uses `scopes-networking` for networking configuration overrides, enable the override flag so the agent appends `--overrides-path` to its command:

```hcl
overrides_enabled      = true
overrides_repo_path    = "/root/.np/nullplatform/scopes-networking"
overrides_service_path = "/lambda"
```

This results in the agent running:
```
/root/.np/nullplatform/scopes-lambda/lambda/entrypoint \
  --service-path=.../lambda \
  --overrides-path=/root/.np/nullplatform/scopes-networking/lambda
```

## Updating specs

To push spec changes after editing templates in `install/specs/`:

1. Merge your branch to `main` (or update `github_branch` in tfvars)
2. Run `tofu apply` — the module fetches templates from GitHub raw on each run
