data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda" {
  count = var.iam_create_role ? 1 : 0

  name = var.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  permissions_boundary = var.iam_permissions_boundary != "" ? var.iam_permissions_boundary : null

  tags = local.iam_default_tags
}

# Attach managed policies
resource "aws_iam_role_policy_attachment" "managed" {
  count = var.iam_create_role ? length(local.iam_managed_policies) : 0

  role       = aws_iam_role.lambda[0].name
  policy_arn = local.iam_managed_policies[count.index]
}

# Attach custom inline policies
resource "aws_iam_role_policy" "custom" {
  count = var.iam_create_role ? length(var.iam_role_policies) : 0

  name   = var.iam_role_policies[count.index].name
  role   = aws_iam_role.lambda[0].id
  policy = var.iam_role_policies[count.index].policy
}

# CloudWatch Logs — scoped to the Lambda's own log group.
# Replaces the AWSLambdaBasicExecutionRole managed policy which grants logs:* on Resource: *.
resource "aws_iam_role_policy" "cloudwatch_logs" {
  count = var.iam_create_role ? 1 : 0

  name = "cloudwatch-logs"
  role = aws_iam_role.lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.iam_function_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.iam_function_name}:*"
      }
    ]
  })
}

# ECR pull permissions — scoped to repositories in the same account.
# ecr:GetAuthorizationToken requires Resource: * (AWS limitation).
# The placeholder Lambda always uses a container image regardless of scope package type,
# so ECR access is required from the first deployment onward.
resource "aws_iam_role_policy" "ecr" {
  count = var.iam_create_role ? 1 : 0

  name = "ecr-image-pull"
  role = aws_iam_role.lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      }
    ]
  })
}

# Secrets Manager read access — scoped to all secrets for this scope (wildcard covers all deployments).
# Uses a wildcard ARN so the role is valid for every deployment without requiring policy updates.
resource "aws_iam_role_policy" "secrets_manager_scope" {
  count = var.iam_create_role && var.iam_scope_id != "" ? 1 : 0

  name = "secrets-manager-parameters-read"
  role = aws_iam_role.lambda[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:*:*:secret:nullplatform/${var.iam_scope_id}/*"
      }
    ]
  })
}
