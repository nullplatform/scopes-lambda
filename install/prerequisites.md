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
