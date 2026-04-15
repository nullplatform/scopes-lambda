output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = local.lambda_role_arn
}

output "iam_role_name" {
  description = "Name of the IAM role"
  value       = var.iam_create_role ? aws_iam_role.lambda[0].name : ""
}

output "iam_role_id" {
  description = "ID of the IAM role"
  value       = var.iam_create_role ? aws_iam_role.lambda[0].id : ""
}
