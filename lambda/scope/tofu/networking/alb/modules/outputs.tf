output "alb_target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.lambda.arn
}

output "alb_target_group_name" {
  description = "Name of the target group"
  value       = aws_lb_target_group.lambda.name
}

output "alb_listener_rule_arn" {
  description = "ARN of the listener rule"
  value       = aws_lb_listener_rule.lambda.arn
}

output "alb_host_header" {
  description = "Host header used for routing"
  value       = var.alb_host_header
}
