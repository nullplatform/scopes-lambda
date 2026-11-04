variable "installation" {
  description = "The installation this module serves: its id, the NRN it was installed at, and the package slug and version."
  type = object({
    id           = string
    nrn          = string
    package_slug = string
    version      = string
  })
}

variable "service_specification_id" {
  description = "Id of the scope's service specification, the one the installed package pins. The scope type points at it and the channel routes by it."
  type        = string
}

# ── Each one received, or found by the caller, or created here ──

variable "scope_type_id" {
  description = "An existing scope type that already points at the specification, reused as is. Null creates one with scope_type_name and scope_type_description."
  type        = string
  default     = null
}

variable "scope_type_name" {
  description = "Name of the scope type developers pick, when one is created. Pick one that tells it apart from a copy's."
  type        = string
  default     = "nullplatform AWS Lambda"
}

variable "scope_type_description" {
  type    = string
  default = "Serverless functions on AWS Lambda"
}

variable "scope_configuration_specification_id" {
  description = "An existing scope-configuration schema (a provider specification), reused as is: the copy's, for instance. Null creates one from the template."
  type        = string
  default     = null
}

variable "scope_configuration_template" {
  description = "Path, relative to this module, of the scope-configuration template the schema is created from: the scope's own specs/ file."
  type        = string
  default     = "../specs/scope-configuration.json.tpl"
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

variable "channel_id" {
  description = "An agent channel that already routes this package at the NRN, reused as is. Null creates one when create_channel is on."
  type        = string
  default     = null
}

variable "create_channel" {
  description = "Create the agent channel that routes the scope's actions to the package worker. Off when the organization creates channels elsewhere."
  type        = bool
  default     = true

  validation {
    condition     = !(var.create_channel && var.channel_id == null) || length(var.agent_tags) > 0
    error_message = "Creating the channel needs agent_tags: the channel selects the agent by them."
  }
}

variable "agent_tags" {
  description = "Tags of the agent that runs this package's worker; the channel selects it by them."
  type        = map(string)
  default     = {}
}
