variable "installation" {
  description = "The installation this target belongs to: its id, the NRN it was installed at, and the package slug and version."
  type = object({
    id           = string
    nrn          = string
    package_slug = string
    version      = string
  })
}

variable "name" {
  description = "Name of this target, unique within the installation (e.g. the environment). Part of the created resources' names."
  type        = string
}

variable "dimensions" {
  description = "Dimensions this target serves; the IAM provider and the scope-configuration created here carry them so the runtime resolves them for scopes in that environment."
  type        = map(string)
  default     = {}
}

variable "agent_role_arn" {
  description = "IAM role the agent's workers run with in this account; the created role trusts it."
  type        = string
}

variable "scope_configuration_slug" {
  description = "Slug of the scope-configuration schema (the installation module's output, or the given schema's) the values are written under."
  type        = string
}

# ── Each one received, or provisioned when absent ──

variable "role_arn" {
  description = "The role the worker assumes. Null creates one in this account, trusting agent_role_arn. Pass role_from_entry when it came from the IAM provider's own lambda entry."
  type        = string
  default     = null

  validation {
    condition     = var.role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:aws:iam::<account>:role/<name>)."
  }
}

variable "role_from_entry" {
  description = "True when role_arn is what the IAM provider already lists under selector lambda: nothing is written to the provider then."
  type        = bool
  default     = false
}

variable "iam_provider_id" {
  description = "The IAM provider the role is registered in under selector \"lambda\". Null creates one at the installation NRN with the target's dimensions; otherwise only this entry is added to it."
  type        = string
  default     = null

  validation {
    condition     = var.iam_provider_id == null || can(regex("^[A-Za-z0-9_-]+$", var.iam_provider_id))
    error_message = "iam_provider_id must be a provider id (letters, digits, '-' and '_')."
  }
}

variable "state_bucket" {
  description = "S3 bucket for the scopes' OpenTofu state. Null creates one."
  type        = string
  default     = null
}

variable "placeholder_image_uri" {
  description = "ECR URI of the Lambda placeholder image. Never built here: null creates the repository (unless placeholder_repository_url names an existing one) and reports the image as missing."
  type        = string
  default     = null
}

variable "placeholder_repository_url" {
  description = "An existing placeholder repository without an image, reused so none is created."
  type        = string
  default     = null
}

variable "alb_listener_arn" {
  description = "Listener of the public ALB scopes attach to. Optional: without it, scopes get no HTTP endpoint through an ALB and it is reported as missing."
  type        = string
  default     = null
}

variable "scope_configuration_id" {
  description = "An existing scope-configuration (provider config) for the target's dimensions, reused as is. Null writes one with the values above once the placeholder image is known."
  type        = string
  default     = null
}

variable "assets_bucket_name" {
  description = "S3 bucket holding Lambda deployment assets; the created role gets read access to it."
  type        = string
  default     = "lambda-files-aws-services"
}
