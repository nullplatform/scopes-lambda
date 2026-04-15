output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.main.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.main.function_name
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.main.invoke_arn
}

output "lambda_alias_arn" {
  description = "ARN of the main alias"
  value       = aws_lambda_alias.main.arn
}

output "lambda_alias_invoke_arn" {
  description = "Invoke ARN of the main alias"
  value       = aws_lambda_alias.main.invoke_arn
}

output "lambda_current_version" {
  description = "Current published version of the Lambda function"
  value       = aws_lambda_function.main.version
}

output "lambda_qualified_arn" {
  description = "Qualified ARN of the Lambda function (with alias)"
  value       = aws_lambda_alias.main.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.arn
}

output "lambda_warmup_alias_arn" {
  description = "ARN of the warmup alias (if configured)"
  value       = local.lambda_create_warmup_alias ? aws_lambda_alias.warmup[0].arn : null
}
