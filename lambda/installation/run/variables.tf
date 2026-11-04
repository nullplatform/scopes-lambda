# Filled by lib/context from NP_INSTALL_CONTEXT, resolving what the installer
# did not give.

variable "installation" {
  type = object({
    id           = string
    nrn          = string
    package_slug = string
    version      = string
  })
}

variable "agent" {
  description = "The agent that runs this package's worker: the IAM role its workers run with and the tags its channel selects it by."
  type = object({
    role_arn = string
    tags     = map(string)
  })
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "service_specification_id" {
  type = string
}

variable "scope_type" {
  description = "`id` when one already points at the specification (reused), else the name and description of the one created."
  type = object({
    id          = optional(string)
    name        = string
    description = string
  })
}

variable "scope_configuration" {
  description = "`id` and `slug` when a schema is already visible (reused); both null creates one from the template."
  type = object({
    id   = optional(string)
    slug = optional(string)
  })
  default = {}
}

variable "channel_id" {
  type    = string
  default = null
}

variable "targets" {
  description = "One target per dimension set the installation serves; the runner has one AWS provider, so one account."
  type = map(object({
    dimensions                 = map(string)
    role_arn                   = optional(string)
    role_from_entry            = optional(bool, false)
    iam_provider_id            = optional(string)
    state_bucket               = optional(string)
    placeholder_image_uri      = optional(string)
    placeholder_repository_url = optional(string)
    alb_listener_arn           = optional(string)
    scope_configuration_id     = optional(string)
  }))

  validation {
    condition     = length(var.targets) > 0
    error_message = "At least one target is required: no cloud provider resolves at the installation NRN and none was given."
  }
}

variable "metrics_provider" {
  type    = string
  default = "externalmetrics"
}

variable "log_provider" {
  type    = string
  default = "external"
}

variable "assets_bucket_name" {
  type    = string
  default = "lambda-files-aws-services"
}

variable "create_channel" {
  type    = bool
  default = true
}
