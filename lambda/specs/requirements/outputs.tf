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

output "lambda_alb_arn" {
  description = "ARN of the public Lambda ALB (empty when install_alb = false)."
  value       = local.alb_create ? aws_lb.lambda_public[0].arn : ""
}

output "lambda_alb_listener_arn" {
  description = "ARN of the HTTPS:443 listener on the Lambda ALB. Publish to the aws-networking-configuration provider (load_balancer.public.listener_arn) so the Lambda scope workflow can attach per-scope rules. Empty when install_alb = false."
  value       = local.alb_create ? aws_lb_listener.lambda_public_https[0].arn : ""
}

output "lambda_alb_dns_name" {
  description = "DNS name of the public Lambda ALB (empty when install_alb = false)."
  value       = local.alb_create ? aws_lb.lambda_public[0].dns_name : ""
}
