locals {
  # Module identifier
  alb_module_name = "networking/alb"

  # Default tags
  alb_default_tags = merge(var.alb_resource_tags_json, {
    ManagedBy = "custom-scope-role"
    Module    = local.alb_module_name
  })

  # Cross-module outputs (consumed by dns layer)
  alb_target_group_arn = aws_lb_target_group.lambda.arn
  alb_listener_rule_arn = aws_lb_listener_rule.lambda.arn
}
