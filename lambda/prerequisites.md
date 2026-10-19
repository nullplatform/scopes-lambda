# AWS Lambda Scope — Agent Prerequisites

## Repositories

The agent pod must have the following repositories cloned at the expected paths:

| Repository | Default path on agent |
|---|---|
| [nullplatform/scopes-lambda](https://github.com/nullplatform/scopes-lambda) | `/root/.np/nullplatform/scopes-lambda` |
| [nullplatform/scopes-networking](https://github.com/nullplatform/scopes-networking) | `/root/.np/nullplatform/scopes-networking` |

Override the default paths via the `repo_path` and `overrides_repo_path` variables in `terraform.tfvars`.

## Required tooling on the agent pod

- `aws` CLI
- `mise` (dependency version manager that is used to install OpenTofu)
- `jq`
- `gomplate`
- `base64`

## AWS IAM Permissions

Agents run in a Kubernetes pod and authenticate to AWS via a **Service Account** (IRSA / Pod Identity). The SA must have an IAM role with the following permissions.

---

### Lambda

```json
{
  "Effect": "Allow",
  "Action": [
    "lambda:CreateFunction",
    "lambda:DeleteFunction",
    "lambda:GetFunction",
    "lambda:GetFunctionConfiguration",
    "lambda:GetFunctionConcurrency",
    "lambda:GetFunctionCodeSigningConfig",
    "lambda:GetAccountSettings",
    "lambda:UpdateFunctionCode",
    "lambda:UpdateFunctionConfiguration",
    "lambda:ListVersionsByFunction",
    "lambda:PublishVersion",
    "lambda:CreateAlias",
    "lambda:UpdateAlias",
    "lambda:DeleteAlias",
    "lambda:GetAlias",
    "lambda:ListAliases",
    "lambda:AddPermission",
    "lambda:RemovePermission",
    "lambda:GetPolicy",
    "lambda:InvokeFunction",
    "lambda:PutFunctionConcurrency",
    "lambda:DeleteFunctionConcurrency",
    "lambda:PutProvisionedConcurrencyConfig",
    "lambda:GetProvisionedConcurrencyConfig",
    "lambda:DeleteProvisionedConcurrencyConfig",
    "lambda:TagResource",
    "lambda:UntagResource",
    "lambda:ListTags"
  ],
  "Resource": "*"
}
```

---

### CloudWatch Logs

```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:DeleteLogGroup",
    "logs:DescribeLogGroups",
    "logs:CreateLogStream",
    "logs:PutLogEvents",
    "logs:FilterLogEvents",
    "logs:GetLogEvents",
    "logs:PutRetentionPolicy",
    "logs:TagLogGroup",
    "logs:ListTagsForResource",
    "logs:TagResource",
    "logs:UntagResource"
  ],
  "Resource": "*"
}
```

---

### CloudWatch Metrics (diagnose / metric actions, ALB rule count)

```json
{
  "Effect": "Allow",
  "Action": [
    "cloudwatch:GetMetricStatistics",
    "cloudwatch:GetMetricData",
    "cloudwatch:ListMetrics",
    "cloudwatch:PutMetricData"
  ],
  "Resource": "*"
}
```

---

### IAM (Lambda execution role management)

```json
{
  "Effect": "Allow",
  "Action": [
    "iam:CreateRole",
    "iam:DeleteRole",
    "iam:GetRole",
    "iam:PassRole",
    "iam:AttachRolePolicy",
    "iam:DetachRolePolicy",
    "iam:PutRolePolicy",
    "iam:DeleteRolePolicy",
    "iam:GetRolePolicy",
    "iam:ListAttachedRolePolicies",
    "iam:ListRolePolicies",
    "iam:TagRole",
    "iam:UntagRole"
  ],
  "Resource": "*"
}
```

> The implementation scopes the `iam:*` actions to the roles the scope manages
> (`arn:aws:iam::*:role/nullplatform-*`, `arn:aws:iam::*:role/np-lambda-*`).
> Narrow the `Resource` accordingly in production instead of `*`.

---

### API Gateway

```json
{
  "Effect": "Allow",
  "Action": [
    "apigateway:GET",
    "apigateway:POST",
    "apigateway:PUT",
    "apigateway:PATCH",
    "apigateway:DELETE",
    "apigateway:TagResource",
    "apigateway:UntagResource"
  ],
  "Resource": "*"
}
```

---

### ALB (Application Load Balancer)

```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:DescribeLoadBalancers",
    "elasticloadbalancing:DescribeLoadBalancerAttributes",
    "elasticloadbalancing:CreateTargetGroup",
    "elasticloadbalancing:DeleteTargetGroup",
    "elasticloadbalancing:ModifyTargetGroup",
    "elasticloadbalancing:ModifyTargetGroupAttributes",
    "elasticloadbalancing:DescribeTargetGroups",
    "elasticloadbalancing:DescribeTargetGroupAttributes",
    "elasticloadbalancing:RegisterTargets",
    "elasticloadbalancing:DeregisterTargets",
    "elasticloadbalancing:DescribeTargetHealth",
    "elasticloadbalancing:CreateRule",
    "elasticloadbalancing:DeleteRule",
    "elasticloadbalancing:ModifyRule",
    "elasticloadbalancing:DescribeRules",
    "elasticloadbalancing:DescribeListeners",
    "elasticloadbalancing:AddTags",
    "elasticloadbalancing:RemoveTags",
    "elasticloadbalancing:DescribeTags"
  ],
  "Resource": "*"
}
```

Only with `networking.alb_autocreate_enabled`:

```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:CreateLoadBalancer",
    "elasticloadbalancing:CreateListener",
    "elasticloadbalancing:ModifyLoadBalancerAttributes",
    "elasticloadbalancing:DescribeListenerCertificates",
    "elasticloadbalancing:AddListenerCertificates"
  ],
  "Resource": "*"
}
```

---

### Route 53

```json
{
  "Effect": "Allow",
  "Action": [
    "route53:ChangeResourceRecordSets",
    "route53:GetHostedZone",
    "route53:ListHostedZones",
    "route53:ListResourceRecordSets",
    "route53:GetChange"
  ],
  "Resource": "*"
}
```

---

### S3 (Terraform state + Zip deployment packages)

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:CreateBucket",
    "s3:HeadBucket",
    "s3:PutBucketVersioning",
    "s3:GetBucketVersioning",
    "s3:GetBucketLocation",
    "s3:ListBucket",
    "s3:ListBucketVersions",
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:DeleteObjectVersion"
  ],
  "Resource": [
    "arn:aws:s3:::<state-bucket>",
    "arn:aws:s3:::<state-bucket>/*",
    "arn:aws:s3:::<assets-bucket>",
    "arn:aws:s3:::<assets-bucket>/*"
  ]
}
```

> **Two distinct buckets.** `<state-bucket>` is where the create/delete
> workflows persist the per-scope OpenTofu state (read/write). `<assets-bucket>`
> is where nullplatform stores the build's Zip deployment packages
> (e.g. `lambda-files-<cluster>`); the role only needs **read** access there
> (`s3:GetObject` + `s3:ListBucket`) so `UpdateFunctionCode` can fetch the Zip.
> They are often different buckets — make sure both are in the `Resource` list,
> otherwise the Zip deployment fails with `AccessDenied` on `s3:GetObject`.

---

### ECR (Docker image deployments)

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:CreateRepository",
    "ecr:DescribeRepositories",
    "ecr:DescribeImages",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchCheckLayerAvailability",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:PutImage",
    "ecr:TagResource",
    "ecr:GetRepositoryPolicy",
    "ecr:SetRepositoryPolicy"
  ],
  "Resource": "*"
}
```

---

### Secrets Manager (deployment parameters)

```json
{
  "Effect": "Allow",
  "Action": [
    "secretsmanager:CreateSecret",
    "secretsmanager:GetSecretValue",
    "secretsmanager:PutSecretValue",
    "secretsmanager:DeleteSecret",
    "secretsmanager:DescribeSecret",
    "secretsmanager:ListSecrets",
    "secretsmanager:TagResource"
  ],
  "Resource": "arn:aws:secretsmanager:*:*:secret:nullplatform/*"
}
```

---

### STS (identity resolution)

```json
{
  "Effect": "Allow",
  "Action": ["sts:GetCallerIdentity"],
  "Resource": "*"
}
```

## Runtime infrastructure and nullplatform provider configurations

The IAM policies above let the agent CREATE Lambda functions and target
groups, but the `create-scope` workflow ALSO depends on three runtime
artifacts that must exist BEFORE the first scope is created. None are
auto-created by the bundled `specs/tofu/main.tf` today — the operator
must provision them.

### 1. Placeholder image (private ECR)

The first step of `create-scope` (`resolve_placeholder_image`) reads
`.deployment.placeholder_image_uri` from a `nullplatform_provider_config`
of category `scope-configurations`. The image is loaded into the new
Lambda function on creation and is later replaced by the user's image
on first deploy.

Publish it with the bundled
[`lambda/scope/placeholder/publish`](../lambda/scope/placeholder/publish)
script. The script:

- Creates a private ECR repository if missing.
- Builds and pushes single-architecture images
  (`<image>:<tag>-arm64` and `<image>:<tag>-amd64`) with Docker Buildx —
  Lambda does not support multi-arch manifest lists.

```bash
export PLACEHOLDER_IMAGE_REPO=<account-id>.dkr.ecr.<region>.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder
cd lambda/scope/placeholder
./publish
```

Apply the `LambdaECRImageRetrievalPolicy` resource policy
(see [ECR Repository Policies](#ecr-repository-policies-resource-policies-not-iam)
below) to the placeholder repository so the Lambda service principal
can pull the image.

### 2. Application Load Balancer

The bundled ALB tofu module (`lambda/scope/tofu/networking/alb/`)
registers a target group and a host-header listener rule per scope on
an existing ALB. The ALBs themselves are the operator's responsibility.

You need, per visibility that uses an ALB (`private` always, `public`
when `networking.public_exposure = "alb"`):

- One or more `aws_lb` of type `application` (internal for private,
  internet-facing for public).
- An HTTPS:443 listener on each, with a certificate covering the scope
  domains (typically a wildcard). The workflow does not check it.
- Their listener ARNs under `networking.alb_<visibility>_listener_arns`
  in the `scope-configurations` provider
  (see step 3).

AWS caps an ALB at 100 rules across all its listeners, counting rules
of other workloads too. New scopes go to the ALB with the fewest rules
below `ALB_LISTENER_RULE_ALERT_THRESHOLD` (75); no new rule is added to
an ALB at `ALB_LISTENER_RULE_CAPACITY` (98). Each create and delete
publishes `nullplatform/ApplicationELB` · `RuleCount` and
`TargetGroupCount` (dimension `ALBName`), the same metrics as the k8s
scope. They are only published on those runs, so alarms need
`treat-missing-data = ignore` to hold their state.

With `networking.alb_autocreate_enabled`, a create that finds every ALB
full clones the first configured one instead of failing: scheme, subnets,
security groups, tags, attributes, certificates, mTLS, and listeners whose
default action is a redirect or fixed response (a forward default becomes
a 404). It is named `<alb_autocreate_name_prefix><visibility>-<n>`, tagged
`nullplatform:lambda-autocreated=<visibility>` and
`nullplatform:lambda-autocreated-from=<template ALB>`, appended to
`networking.alb_<visibility>_listener_arns`, and never deleted by the
workflow. The agent's API key needs write access on the
`scope-configurations` provider; without it the ALB is still used, and
picked up again by name and tags on the next create, keeping its listeners.

Without listeners for a visibility, its scopes get no HTTP exposure.

This replaces the `scopes-networking` Lambda override: disable it on the
agent (`overrides_enabled = false`), or create fails. Scopes it created
keep their rule, and delete removes it; recreate them to move it to the
networking stack.

### 3. Provider configurations

The `create-scope` workflow reads two `nullplatform_provider_config`s
by category. Both must be in place before the first scope is created.

#### `scope-configurations`

This category is **not** auto-created by the bundled installation —
the operator must provision the `nullplatform_provider_config`
manually. The expected attribute schema:

| Path | Type | Required | Description |
|---|---|---|---|
| `deployment.placeholder_image_uri` | string | yes | Full URI of the placeholder image you published in step 1, **without** the architecture suffix. The workflow appends `-arm64` or `-amd64` based on the scope's architecture. |
| `state.tofu_state_bucket` | string | yes | S3 bucket where each Lambda scope writes its OpenTofu state. Each scope uses a unique key prefix, so a single bucket can be shared across all Lambda scopes (and across scope types — e.g. `static-files` reuses the same bucket convention). |
| `state.tofu_state_bucket_region` | string | no | AWS region of the state bucket. Defaults to the `cloud-providers` account region. |
| `networking.alb_public_listener_arns` | list | no | Listeners public ALB scopes are balanced across. |
| `networking.alb_private_listener_arns` | list | no | Same, for private scopes. |
| `networking.public_exposure` | string | no | `alb` or `api_gateway` for public scopes. Defaults to `alb` when `load_balancer.public` listeners are configured, else `api_gateway`. |
| `networking.alb_listener_rule_alert_threshold` | number | no | Rules at which an ALB stops taking new scopes. Default `75`. |
| `networking.alb_listener_rule_capacity` | number | no | Hard cap of rules per ALB, at most `100`. Default `98`. |
| `networking.alb_autocreate_enabled` | bool | no | Clone a new ALB when every ALB is full. Default `false`. |
| `networking.alb_autocreate_name_prefix` | string | no | Name prefix of autocreated ALBs, `[a-z0-9-]`, at most 21 chars. Default `np-lambda-`. |
| `networking.alb_metrics_enabled` | bool | no | Publish the ALB metrics. Default `true`. |
| `networking.alb_metrics_target` | string | no | `cloudwatch` (default) or `datadog`; Datadog needs `DATADOG_API_KEY` (and `DATADOG_SITE` outside `datadoghq.com`) on the agent. |
| `networking.api_gateway_certificate_arn` | string | no | ACM certificate for API Gateway custom domains; without it public scopes use the `execute-api` endpoint. |

Example:

```hcl
resource "nullplatform_provider_config" "scope_configurations" {
  nrn        = "organization=<org-id>:account=<account-id>"
  type       = "scope-configurations"
  dimensions = { environment = "development" }

  attributes = jsonencode({
    deployment = {
      placeholder_image_uri = "<account-id>.dkr.ecr.<region>.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest"
    }
    state = {
      tofu_state_bucket = "<your-tofu-state-bucket>"
      # tofu_state_bucket_region = "<bucket-region>" # optional
    }
  })
}
```

#### `vpc` / `aws-networking-configuration`

`load_balancer.<visibility>.listener_arn` of a `nullplatform_provider_config`
of category `vpc` (the legacy name) or `aws-networking-configuration` is the
single-ALB fallback when `networking.alb_<visibility>_listener_arns` is not set
in `scope-configurations`. That spec drops keys it does not declare, so the
list lives in `scope-configurations`.

Recent schema versions also require `vpc.id`, `vpc.subnets`, and
`vpc.security_groups` on the same config — check the spec your
installation has by querying the API.

Private scopes get their record in `networking.hosted_zone_id` of the
`cloud-providers` config, falling back to `hosted_public_zone_id`.

## ECR Repository Policies (resource policies, not IAM)

The IAM policies above govern what the **agent's role** can do. They do
not govern what the **AWS Lambda service principal** can do, which is a
separate concern: when Lambda's `CreateFunction` and `UpdateFunctionCode`
APIs pull a container image from ECR, the call is made by the
`lambda.amazonaws.com` service principal — not by the agent's role.

By default the Lambda service principal has **no implicit access** to
private ECR repositories in the customer's account. Each ECR repository
that holds a Lambda image must therefore have a resource-based policy
allowing the Lambda service to pull. Without this policy, the deploy
workflow's `update_function_code` step fails with:

```
api error AccessDeniedException: Lambda does not have permission to
access the ECR image. Check the ECR permissions.
```

This applies to **every** ECR repository that ever stores a Lambda
image:

1. The placeholder ECR (created during installation, addressed by
   `lambda/specs/tofu/main.tf` if you use the bundled module — the policy is
   already applied there).
2. **The per-application ECR repositories** that `np asset push`
   creates dynamically when each app does its first build, named
   `<namespace_slug>/<application_slug>`. **These need the same policy
   applied — the bundled installation module does NOT set it up for
   per-app repos today, which is the most common cause of the first
   real deploy failing on a new installation.**
3. Any other ECR repository you may use to host Lambda images (custom
   per-team repos, shared base images, etc.).

### Policy to apply

The policy is the same in every case:

```hcl
resource "aws_ecr_repository_policy" "lambda_image_pull" {
  repository = "<ecr-repo-name>"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LambdaECRImageRetrievalPolicy"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "<aws-account-id>"
          }
        }
      },
    ]
  })
}
```

The `aws:SourceAccount` condition restricts the trust to Lambda
functions in your own account. AWS recommends this exact pattern in the
[ECR repository policy docs](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html).

### Recommended pattern for per-application ECRs

Because per-application ECRs are created on-demand by `np asset push`,
declaring a static `aws_ecr_repository_policy` resource per app does
not scale — every new Lambda Application needs a manual TF change.

The recommended approach is an
[`aws_ecr_repository_creation_template`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_creation_template)
matching the namespace prefix used by your `np asset push` invocations
(typically `<namespace_slug>/`):

```hcl
resource "aws_ecr_repository_creation_template" "lambda_app_repos" {
  prefix       = "<namespace_slug>/"
  description  = "Auto-apply LambdaECRImageRetrievalPolicy to per-app ECR repos"
  applied_for  = ["PULL_THROUGH_CACHE", "REPLICATION"] # adjust to your needs

  repository_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LambdaECRImageRetrievalPolicy"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "<aws-account-id>"
          }
        }
      },
    ]
  })
}
```

> **Important:** repository creation templates apply only to ECR
> repositories created **after** the template is in place. ECR repos
> that already exist must still be patched with explicit
> `aws_ecr_repository_policy` resources (or a one-off
> `aws ecr set-repository-policy` call) — the template is forward-only.
