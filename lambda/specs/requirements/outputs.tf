output "permissions_role_arn" {
  description = "ARN of the Lambda permissions role assumed by the nullplatform agent role. Pass to the agent (assume_role_arns) and publish to the AWS IAM provider (selector \"lambda\")."
  value       = local.iam_create ? aws_iam_role.nullplatform_lambda[0].arn : ""
}

output "permissions_role_name" {
  description = "Name of the Lambda permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_lambda[0].name : ""
}

output "permissions_role_id" {
  description = "ID of the Lambda permissions role"
  value       = local.iam_create ? aws_iam_role.nullplatform_lambda[0].id : ""
}

output "placeholder_image_repository_url" {
  description = "URL of the private ECR repository holding the Lambda placeholder image. Consumed by the agent via PLACEHOLDER_IMAGE_URI_DEFAULT."
  value       = local.iam_create ? aws_ecr_repository.lambda_placeholder[0].repository_url : ""
}
