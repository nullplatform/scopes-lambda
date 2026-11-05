variable "installation" {
  description = "The installation this account belongs to: its id, the NRN it was installed at, and the package slug and version."
  type = object({
    id           = string
    nrn          = string
    package_slug = string
    version      = string
  })
}

variable "name" {
  description = "Name of this account within the installation (e.g. dev, prod). Part of the created resources' names."
  type        = string
}

variable "agent_role_arn" {
  description = "IAM role the agent's workers run with in this account; the created role trusts it."
  type        = string
}

# ── Each one received, or provisioned when absent ──

variable "role_arn" {
  description = "The role the worker assumes in this account. Null creates one, trusting agent_role_arn."
  type        = string
  default     = null

  validation {
    condition     = var.role_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.role_arn))
    error_message = "role_arn must be an IAM role ARN (arn:aws:iam::<account>:role/<name>)."
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

variable "assets_bucket_name" {
  description = "S3 bucket holding Lambda deployment assets; the created role gets read access to it."
  type        = string
  default     = "lambda-files-aws-services"
}
