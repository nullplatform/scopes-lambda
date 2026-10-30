variable "nrn" {
  description = "NRN of your organization where the scope is installed (e.g. organization=123:account=456). The package is looked up as visible there, and the installation, scope type, NRN settings and scope-configuration schema are created there."
  type        = string
}

variable "visible_to" {
  description = "Where inside your organization the scope can be used. Defaults to [nrn]. Every entry must be under your organization."
  type        = list(string)
  default     = null
}

variable "np_api_key" {
  description = "nullplatform API key for the `np nrn patch` that sets the scope's metrics and logs providers. Null uses the NP_API_KEY of the environment running the apply."
  type        = string
  default     = null
  sensitive   = true
}

variable "external_metrics_provider" {
  description = "Metrics provider recorded in the NRN settings for this scope."
  type        = string
  default     = "externalmetrics"
}

variable "external_logging_provider" {
  description = "Logs provider recorded in the NRN settings for this scope."
  type        = string
  default     = "external"
}

variable "scope_type_name" {
  description = "Name of the scope type developers pick. Override it when your organization already has a scope type with this name, registered with specs/install."
  type        = string
  default     = "AWS Lambda"
}

variable "scope_type_description" {
  description = "Description of the scope type."
  type        = string
  default     = "Serverless functions on AWS Lambda"
}

variable "create_scope_configuration" {
  description = "Create the scope-configuration provider specification. Set it to false when your organization already has the one specs/install created: the scope reads every scope-configurations provider at the NRN, so your existing settings keep serving it."
  type        = bool
  default     = true
}

variable "scope_configuration_name" {
  description = "Name of the scope-configuration provider specification. Null uses the template's (\"AWS Lambda\"); override it when that name collides with one already visible in your organization."
  type        = string
  default     = null
}
