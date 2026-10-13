locals {
  # Module identifier
  alb_module_name = "networking/alb"

  # Default tags
  alb_default_tags = merge(var.alb_resource_tags_json, {
    ManagedBy = "custom-scope-role"
    Module    = local.alb_module_name
  })
}
