# ── Injected from NP_INSTALL_CONTEXT by lib/context; never written by the installer ──

variable "installation" {
  description = "The installation this run belongs to: its id, the NRN it was installed at, and the package slug and version."
  type = object({
    id           = string
    nrn          = string
    package_slug = string
    version      = string
  })
}

variable "agent" {
  description = "The agent that runs this package's worker: the IAM role its workers run with (trusted by every role created here) and the tags its channel selects it by."
  type = object({
    role_arn = string
    tags     = map(string)
  })
}

variable "aws_region" {
  description = "Region of the AWS API endpoint; lib/context sets it from the first target's cloud provider."
  type        = string
  default     = "us-east-1"
}

variable "service_specification_id" {
  description = "Id of the scope's service specification, the one the installed package pins. The scope type points at it and the channel routes by it. lib/context resolves it by the package slug."
  type        = string
}

# ── Per installation: resolved by lib/context, adopted when they already exist ──

variable "scope_type" {
  description = "The scope type developers pick. `id` is set when one already points at the specification (adopted); otherwise one is created with `name` and `description`."
  type = object({
    id          = optional(string)
    name        = string
    description = string
  })
}

variable "scope_configuration" {
  description = "The scope-configuration schema (a provider specification). `id` is set when one with `slug` is already visible (adopted, the copy's for instance); otherwise it is created from specs/scope-configuration.json.tpl."
  type = object({
    id   = optional(string)
    slug = string
  })
}

variable "scope_configuration_template" {
  description = "Path, relative to this module, of the scope-configuration template the schema is created from. The scope's own specs/ file here; lib/context copies it next to the module in the working directory."
  type        = string
  default     = "../specs/scope-configuration.json.tpl"
}

variable "channel_id" {
  description = "An agent channel that already routes this package at the NRN, adopted as is. Null creates one."
  type        = string
  default     = null
}

# ── Parameters: each one is received, or resolved here when absent ──

variable "targets" {
  description = <<-EOT
    One target per cloud provider the installation NRN resolves, keyed by a name
    the installer chooses (lib/context derives it from the dimensions when it
    discovers them). Per target, every field but `dimensions` is a parameter
    that lib/context resolves when absent:
      role_arn               the role the worker assumes; discovered in the IAM
                             provider under selector "lambda", else created
      role_from_entry        true when role_arn came from that entry (adopted)
      iam_provider_id        the IAM provider for the target's dimensions; created when none
      state_bucket           the OpenTofu state bucket; discovered in an existing
                             scope-configuration, else created
      placeholder_image_uri  the placeholder image; discovered in an existing
                             scope-configuration or in ECR; never built here
      placeholder_repository_url  an existing placeholder repository without an
                             image, adopted so none is created
      alb_listener_arn       the public ALB listener; discovered in the networking
                             provider; optional
      scope_configuration_id an existing scope-configuration for the dimensions,
                             adopted as is; null creates one with the values above
  EOT
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

  validation {
    condition     = alltrue([for target in var.targets : target.role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", target.role_arn))])
    error_message = "role_arn must be an IAM role ARN (arn:aws:iam::<account>:role/<name>)."
  }

  validation {
    condition     = alltrue([for target in var.targets : target.iam_provider_id == null || can(regex("^[A-Za-z0-9_-]+$", target.iam_provider_id))])
    error_message = "iam_provider_id must be a provider id (letters, digits, '-' and '_')."
  }
}

variable "metrics_provider" {
  description = "Metrics provider recorded in the NRN settings for this scope type."
  type        = string
  default     = "externalmetrics"
}

variable "log_provider" {
  description = "Logs provider recorded in the NRN settings for this scope type."
  type        = string
  default     = "external"
}

variable "assets_bucket_name" {
  description = "S3 bucket holding Lambda deployment assets; the created role gets read access to it."
  type        = string
  default     = "lambda-files-aws-services"
}

variable "create_channel" {
  description = "Create the agent channel that routes the scope's actions to the package worker. Off when the organization creates channels elsewhere."
  type        = bool
  default     = true
}
