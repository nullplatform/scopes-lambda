# Lambda target group
resource "aws_lb_target_group" "lambda" {
  name        = var.alb_target_group_name
  target_type = "lambda"

  dynamic "health_check" {
    for_each = var.alb_health_check_enabled ? [1] : []
    content {
      enabled             = true
      path                = var.alb_health_check_path
      interval            = 35
      timeout             = 30
      healthy_threshold   = 2
      unhealthy_threshold = 2
      matcher             = "200-299"
    }
  }

  tags = local.alb_default_tags
}

# Attach Lambda to target group
resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = local.lambda_alias_arn

  depends_on = [aws_lambda_permission.alb]
}

# Listener rule for routing
resource "aws_lb_listener_rule" "lambda" {
  listener_arn = var.alb_listener_arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    host_header {
      values = [var.alb_host_header]
    }
  }

  tags = local.alb_default_tags
}

# Lambda permission for ALB
resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = local.lambda_function_name
  qualifier     = local.lambda_main_alias_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}
