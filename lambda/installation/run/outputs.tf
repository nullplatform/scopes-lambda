# The installation's report, in the shape the runner prints (README).

output "outputs" {
  value = {
    scope_type_id                     = module.installation.scope_type_id
    scope_configuration_specification = module.installation.scope_configuration_specification_id
    channel_id                        = module.installation.channel_id
    role_arn                          = { for name, target in module.target : name => target.role_arn }
    state_bucket                      = { for name, target in module.target : name => target.state_bucket }
    placeholder_image_uri             = { for name, target in module.target : name => target.placeholder_image_uri }
  }
}

output "resources" {
  value = concat(module.installation.resources, flatten([for target in module.target : target.resources]))
}

output "missing" {
  value = flatten([for target in module.target : target.missing])
}
