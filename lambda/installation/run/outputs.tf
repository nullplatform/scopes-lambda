# The installation's report, in the shape the runner prints (README).

output "outputs" {
  value = {
    scope_type_id                     = module.installation.scope_type_id
    scope_configuration_specification = module.installation.scope_configuration_specification_id
    role_arn                          = module.account.role_arn
    state_bucket                      = module.account.state_bucket
    placeholder_image_uri             = module.account.placeholder_image_uri
    placeholder_repository_url        = module.account.placeholder_repository_url
    iam_provider_id                   = { for name, environment in module.environment : name => environment.iam_provider_id }
    scope_configuration_id            = { for name, environment in module.environment : name => environment.scope_configuration_id }
    channel_id                        = { for name, environment in module.environment : name => environment.channel_id }
  }
}

output "resources" {
  value = concat(module.installation.resources, module.account.resources, flatten([for environment in module.environment : environment.resources]))
}

output "missing" {
  value = concat(module.account.missing, flatten([for environment in module.environment : environment.missing]))
}
