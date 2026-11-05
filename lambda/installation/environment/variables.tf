variable "installation" {
  description = "The installation this environment belongs to: its id, the NRN it was installed at, and the package slug and version."
  type = object({
    id           = string
    nrn          = string
    package_slug = string
    version      = string
  })
}

variable "name" {
  description = "Name of this environment, unique within the installation. Part of the channel's description."
  type        = string
}

variable "dimensions" {
  description = "Dimensions this environment serves; the IAM provider, the scope-configuration and the channel's filter carry them so the runtime resolves them for scopes in it. Empty serves every scope at the NRN."
  type        = map(string)
  default     = {}
}

# ── From the account the environment runs in (account/'s outputs) ──

variable "role_arn" {
  description = "The role the worker assumes in this environment's account; registered in the IAM provider under selector lambda."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:aws:iam::<account>:role/<name>)."
  }
}

variable "role_from_entry" {
  description = "True when role_arn is what the IAM provider already lists under selector lambda: nothing is written to the provider then."
  type        = bool
  default     = false
}

variable "state_bucket" {
  description = "The scopes' OpenTofu state bucket in that account, written in the scope-configuration."
  type        = string
}

variable "state_bucket_region" {
  description = "Region of the state bucket, written next to it."
  type        = string
}

variable "placeholder_image_uri" {
  description = "ECR URI of the Lambda placeholder image in that account. Null until it is published: the scope-configuration is written only once it is known."
  type        = string
  default     = null
}

variable "scope_configuration_slug" {
  description = "Slug of the scope-configuration schema (the installation module's output, or the given schema's) the values are written under."
  type        = string
}

# ── Each one received, or provisioned when absent ──

variable "iam_provider_id" {
  description = "The IAM provider the role is registered in under selector \"lambda\". Null creates one at the installation NRN with the environment's dimensions; otherwise only this entry is added to it."
  type        = string
  default     = null

  validation {
    condition     = var.iam_provider_id == null || can(regex("^[A-Za-z0-9_-]+$", var.iam_provider_id))
    error_message = "iam_provider_id must be a provider id (letters, digits, '-' and '_')."
  }
}

variable "scope_configuration_id" {
  description = "An existing scope-configuration (provider config) for the environment's dimensions, reused as is. Null writes one with the account's values once the placeholder image is known."
  type        = string
  default     = null
}

# ── The agent channel, one per environment ──

variable "service_specification_id" {
  description = "Id of the scope's service specification; the channel routes its actions by it."
  type        = string
}

variable "agent_tags" {
  description = "Tags of the agent that runs this package's worker for this environment; the channel selects it by them. Required with create_channel."
  type        = map(string)
  default     = {}
}

variable "channel_id" {
  description = "An agent channel that already routes this package for these dimensions, reused as is. Null creates one when create_channel is on."
  type        = string
  default     = null
}

variable "create_channel" {
  description = "Create the agent channel that routes this environment's scopes to the package worker. Off when the organization creates channels elsewhere."
  type        = bool
  default     = true

  validation {
    condition     = !(var.create_channel && var.channel_id == null) || length(var.agent_tags) > 0
    error_message = "Creating the channel needs agent_tags: the channel selects the agent by them."
  }
}
