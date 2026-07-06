################################################################################
# AWS Lambda scope — assume-role IAM
#
# Unlike scopes whose permissions are attached directly to the agent role, the
# Lambda scope uses the ASSUME-ROLE pattern: a dedicated role holds the Lambda
# permissions and the agent assumes it (sts:AssumeRole). The consuming stack
# passes this role's ARN to the agent (assume_role_arns) and publishes it to the
# nullplatform AWS IAM provider (selector "lambda").
#
# The role trusts the agent role BY NAME (derived default) rather than by a
# module output, so the consuming stack can wire the ARN back into the agent
# without creating a dependency cycle. The agent role name is the conventional
# "nullplatform-{cluster_name}-agent-role".
#
# Policies are split in four to stay under the IAM policy size limit.
################################################################################

resource "aws_iam_role" "nullplatform_lambda" {
  count = local.iam_create ? 1 : 0

  name        = local.role_name
  description = "Permissions role assumed by the nullplatform agent role for the Lambda scope"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = concat([local.agent_role_arn], var.additional_agent_role_arns) }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.iam_default_tags
}

# --- Lambda core: manage functions, versions, aliases, concurrency, invoke ---
resource "aws_iam_policy" "nullplatform_lambda_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_lambda_policy"
  description = "Policy for managing Lambda functions provisioned by the scopes-lambda provider"
  tags        = local.iam_default_tags

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
          "lambda:GetFunctionCodeSigningConfig",
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
          "lambda:ListTags",
        ]
        Resource = "*"
      }
    ]
  })
}

# --- IAM management: create/manage Lambda execution roles (scoped) -----------
resource "aws_iam_policy" "nullplatform_lambda_iam_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_lambda_iam_policy"
  description = "Policy for managing IAM execution roles for Lambda scopes"
  tags        = local.iam_default_tags

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
          "iam:PassRole",
        ]
        Resource = [
          "arn:aws:iam::*:role/nullplatform-*",
          "arn:aws:iam::*:role/np-lambda-*",
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

# --- Networking: API Gateway, ALB target groups/listener rules, Route53 ------
resource "aws_iam_policy" "nullplatform_lambda_networking_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_lambda_networking_policy"
  description = "Policy for managing API Gateway, ALB, and Route53 for Lambda scopes"
  tags        = local.iam_default_tags

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
          "apigateway:UntagResource",
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
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ListHostedZones",
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Storage & observability: ECR, Secrets Manager, CloudWatch, S3 tfstate ---
resource "aws_iam_policy" "nullplatform_lambda_storage_policy" {
  count = local.iam_create ? 1 : 0

  name        = "${local.policies_name_prefix}_lambda_storage_policy"
  description = "Policy for ECR, Secrets Manager, CloudWatch, and S3 tfstate for Lambda scopes"
  tags        = local.iam_default_tags

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
          "ecr:SetRepositoryPolicy",
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
          "secretsmanager:TagResource",
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
          "logs:UntagResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
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
          "s3:DeleteObjectVersion",
        ]
        Resource = [
          "arn:aws:s3:::nullplatform-lambda-tfstate-*",
          "arn:aws:s3:::nullplatform-lambda-tfstate-*/*",
        ]
      },
      {
        Sid    = "S3Assets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.assets_bucket_name}",
          "arn:aws:s3:::${var.assets_bucket_name}/*",
        ]
      }
    ]
  })
}

# --- Attach the four policies to the assume-role ----------------------------
resource "aws_iam_role_policy_attachment" "lambda" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_lambda[0].name
  policy_arn = aws_iam_policy.nullplatform_lambda_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "lambda_iam" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_lambda[0].name
  policy_arn = aws_iam_policy.nullplatform_lambda_iam_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "lambda_networking" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_lambda[0].name
  policy_arn = aws_iam_policy.nullplatform_lambda_networking_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "lambda_storage" {
  count = local.iam_create ? 1 : 0

  role       = aws_iam_role.nullplatform_lambda[0].name
  policy_arn = aws_iam_policy.nullplatform_lambda_storage_policy[0].arn
}

################################################################################
# Lambda placeholder image registry
#
# Lambda container functions must pull their image from a PRIVATE ECR repo in
# the same account/region (public.ecr.aws is rejected). Scope creation bootstraps
# each Lambda with this placeholder image until the first real deployment
# replaces it. The consuming stack points the agent at this repo via
# PLACEHOLDER_IMAGE_URI_DEFAULT (repository_url is exported as an output).
#
# Terraform manages the repository and the pull policy; it does NOT push images.
# The placeholder image must be mirrored once (requires `crane`):
#
#   ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
#   REGISTRY="$ACCOUNT.dkr.ecr.<region>.amazonaws.com"
#   aws ecr get-login-password --region <region> \
#     | crane auth login --username AWS --password-stdin "$REGISTRY"
#   for arch in amd64 arm64; do
#     crane copy --platform linux/$arch \
#       public.ecr.aws/nullplatform/aws-lambda/nullplatform-lambda-placeholder:latest \
#       "$REGISTRY/aws-lambda/nullplatform-lambda-placeholder:latest-$arch"
#   done
################################################################################

resource "aws_ecr_repository" "lambda_placeholder" {
  count = local.iam_create ? 1 : 0

  name                 = var.placeholder_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.iam_default_tags
}

# Allow the Lambda service to pull the placeholder image.
resource "aws_ecr_repository_policy" "lambda_placeholder" {
  count = local.iam_create ? 1 : 0

  repository = aws_ecr_repository.lambda_placeholder[0].name

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Sid       = "LambdaECRImageRetrievalPolicy"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
      ]
    }]
  })
}
