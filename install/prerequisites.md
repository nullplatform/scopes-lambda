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
    "lambda:UpdateFunctionCode",
    "lambda:UpdateFunctionConfiguration",
    "lambda:ListVersionsByFunction",
    "lambda:PublishVersion",
    "lambda:CreateAlias",
    "lambda:UpdateAlias",
    "lambda:DeleteAlias",
    "lambda:GetAlias",
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
    "logs:PutRetentionPolicy",
    "logs:DescribeLogGroups",
    "logs:TagLogGroup",
    "logs:TagResource",
    "logs:UntagResource"
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

---

### ALB (Application Load Balancer)

```json
{
  "Effect": "Allow",
  "Action": [
    "elasticloadbalancing:CreateTargetGroup",
    "elasticloadbalancing:DeleteTargetGroup",
    "elasticloadbalancing:ModifyTargetGroup",
    "elasticloadbalancing:DescribeTargetGroups",
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
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket",
    "s3:GetBucketVersioning",
    "s3:GetBucketLocation"
  ],
  "Resource": [
    "arn:aws:s3:::<state-bucket>",
    "arn:aws:s3:::<state-bucket>/*"
  ]
}
```

---

### ECR (Docker image deployments)

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer",
    "ecr:DescribeImages"
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
   `install/tofu/main.tf` if you use the bundled module — the policy is
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
