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

# ECR pull permissions — always added when creating the role.
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
        Resource = "*"
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
