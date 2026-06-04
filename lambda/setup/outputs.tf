output "lambda_policy_arn" {
  description = "ARN of the Lambda core management policy"
  value       = aws_iam_policy.nullplatform_lambda_policy.arn
}

output "lambda_iam_policy_arn" {
  description = "ARN of the IAM execution role management policy"
  value       = aws_iam_policy.nullplatform_lambda_iam_policy.arn
}

output "lambda_networking_policy_arn" {
  description = "ARN of the networking policy (API GW + ALB + Route53)"
  value       = aws_iam_policy.nullplatform_lambda_networking_policy.arn
}

output "lambda_storage_policy_arn" {
  description = "ARN of the storage & observability policy (ECR + SM + CW + S3)"
  value       = aws_iam_policy.nullplatform_lambda_storage_policy.arn
}

output "role_arn" {
  description = "ARN of the IAM role created by this module. Empty string when create_role is false."
  value       = var.create_role ? aws_iam_role.nullplatform_lambda_role[0].arn : ""
}

output "role_name" {
  description = "Name of the IAM role created by this module. Empty string when create_role is false."
  value       = var.create_role ? aws_iam_role.nullplatform_lambda_role[0].name : ""
}
