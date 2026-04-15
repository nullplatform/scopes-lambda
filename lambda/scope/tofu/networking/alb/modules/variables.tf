variable "alb_listener_arn" {
  description = "ARN of the ALB listener"
  type        = string
}

variable "alb_target_group_name" {
  description = "Name of the target group"
  type        = string
}

variable "alb_host_header" {
  description = "Host header for routing"
  type        = string
}

variable "alb_rule_priority" {
  description = "Priority for the listener rule"
  type        = number
  default     = 100
}

variable "alb_health_check_path" {
  description = "Path for health check"
  type        = string
  default     = "/health"
}

variable "alb_health_check_enabled" {
  description = "Whether health check is enabled"
  type        = bool
  default     = true
}

variable "alb_resource_tags_json" {
  description = "Tags to apply to ALB resources"
  type        = map(string)
  default     = {}
}
