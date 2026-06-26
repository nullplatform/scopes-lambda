################################################################################
# IAM role (only when create_role = true)
################################################################################

resource "aws_iam_role" "nullplatform_lambda_role" {
  count = var.create_role ? 1 : 0
  name  = "nullplatform_${var.name}_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = var.trusted_arns }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

################################################################################
# Policy attachments
################################################################################

locals {
  effective_role_name = var.create_role ? aws_iam_role.nullplatform_lambda_role[0].name : var.role_name
  attach_policies     = var.create_role || var.role_name != null
}

resource "aws_iam_role_policy_attachment" "lambda" {
  count      = local.attach_policies ? 1 : 0
  role       = local.effective_role_name
  policy_arn = aws_iam_policy.nullplatform_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_iam" {
  count      = local.attach_policies ? 1 : 0
  role       = local.effective_role_name
  policy_arn = aws_iam_policy.nullplatform_lambda_iam_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_networking" {
  count      = local.attach_policies ? 1 : 0
  role       = local.effective_role_name
  policy_arn = aws_iam_policy.nullplatform_lambda_networking_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_storage" {
  count      = local.attach_policies ? 1 : 0
  role       = local.effective_role_name
  policy_arn = aws_iam_policy.nullplatform_lambda_storage_policy.arn
}

################################################################################
# Lambda core policy
# Manages Lambda functions, versions, aliases, concurrency, and invocations.
################################################################################

resource "aws_iam_policy" "nullplatform_lambda_policy" {
  name        = "nullplatform_${var.name}_lambda_policy"
  description = "Policy for managing Lambda functions provisioned by the scopes-lambda provider"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:GetFunctionConcurrency",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:PublishVersion",
          "lambda:ListVersionsByFunction",
          "lambda:GetAlias",
          "lambda:ListAliases",
          "lambda:CreateAlias",
          "lambda:UpdateAlias",
          "lambda:DeleteAlias",
          "lambda:InvokeFunction",
          "lambda:PutFunctionConcurrency",
          "lambda:DeleteFunctionConcurrency",
          "lambda:PutProvisionedConcurrencyConfig",
          "lambda:DeleteProvisionedConcurrencyConfig",
          "lambda:GetProvisionedConcurrencyConfig",
          "lambda:GetAccountSettings",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# IAM management policy
# Creates and manages Lambda execution roles (scoped to nullplatform roles).
################################################################################

resource "aws_iam_policy" "nullplatform_lambda_iam_policy" {
  name        = "nullplatform_${var.name}_lambda_iam_policy"
  description = "Policy for managing IAM execution roles for Lambda scopes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:GetRole",
          "iam:DeleteRole",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/nullplatform-*",
          "arn:aws:iam::*:role/np-lambda-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Networking policy
# API Gateway (HTTP APIs), ALB (target groups + listener rules), Route53 DNS.
################################################################################

resource "aws_iam_policy" "nullplatform_lambda_networking_policy" {
  name        = "nullplatform_${var.name}_lambda_networking_policy"
  description = "Policy for managing API Gateway, ALB, and Route53 for Lambda scopes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PUT",
          "apigateway:PATCH",
          "apigateway:DELETE",
          "apigateway:TagResource",
          "apigateway:UntagResource"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:CreateListenerRule",
          "elasticloadbalancing:DeleteListenerRule",
          "elasticloadbalancing:ModifyListenerRule",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ListHostedZones"
        ]
        Resource = "*"
      }
    ]
  })
}

################################################################################
# Storage & Observability policy
# ECR (placeholder image), Secrets Manager (deployment parameters),
# CloudWatch Logs & Metrics, S3 (tfstate bucket).
################################################################################

resource "aws_iam_policy" "nullplatform_lambda_storage_policy" {
  name        = "nullplatform_${var.name}_lambda_storage_policy"
  description = "Policy for ECR, Secrets Manager, CloudWatch, and S3 tfstate for Lambda scopes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECR"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:TagResource",
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:DeleteSecret",
          "secretsmanager:TagResource"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:nullplatform/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
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
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Tfstate"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:HeadBucket",
          "s3:PutBucketVersioning",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::nullplatform-lambda-tfstate-*",
          "arn:aws:s3:::nullplatform-lambda-tfstate-*/*"
        ]
      }
    ]
  })
}
