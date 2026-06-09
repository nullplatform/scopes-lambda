################################################################################
# Required
################################################################################

variable "nrn" {
  description = "Nullplatform Resource Name (organization:account format)"
  type        = string
}

variable "np_api_key" {
  description = "Nullplatform API key for authentication"
  type        = string
  sensitive   = true
}

variable "tags_selectors" {
  description = "Map of tags used to select the agent that will handle this scope's notification channel"
  type        = map(string)
}

################################################################################
# Repository
################################################################################

variable "github_raw_url" {
  description = "Base URL for fetching raw files from GitHub (without trailing slash)"
  type        = string
  default     = "https://raw.githubusercontent.com/nullplatform/scopes-lambda/refs/heads"
}

variable "github_branch" {
  description = "Git branch to use when fetching spec templates"
  type        = string
  default     = "main"
}

variable "repo_path" {
  description = "Local path where the scopes-lambda repository is cloned on the agent"
  type        = string
  default     = "/root/.np/nullplatform/scopes-lambda"
}

################################################################################
# Scope Definition
################################################################################

variable "service_spec_name" {
  description = "Display name for the scope type in nullplatform"
  type        = string
  default     = "AWS Lambda"
}

variable "service_spec_description" {
  description = "Description of the scope type"
  type        = string
  default     = "AWS Lambda functions managed by nullplatform"
}

variable "external_metrics_provider" {
  description = "Name of the external metrics provider"
  type        = string
  default     = "externalmetrics"
}

variable "external_logging_provider" {
  description = "Name of the external logging provider"
  type        = string
  default     = "external"
}

variable "service_path" {
  description = "Path to the spec definition"
  type        = string
  default     = "lambda"
}

################################################################################
# Overrides
################################################################################

variable "overrides_enabled" {
  description = "Append --overrides-path to the agent cmdline for local config overrides"
  type        = bool
  default     = false
}

variable "overrides_repo_path" {
  description = "Base path of the overrides repository on the agent (e.g. /root/.np/nullplatform/scopes-networking)"
  type        = string
  default     = null
}

variable "overrides_service_path" {
  description = "Service subfolder within the overrides repository (e.g. /lambda)"
  type        = string
  default     = null
}

################################################################################
# IAM permissions (requirements)
# Policies the agent needs to operate Lambda scopes. IAM is global, but the AWS
# provider still needs a region to initialize.
################################################################################

variable "aws_region" {
  description = "AWS region used to initialize the AWS provider. IAM resources are global; leave null to resolve from the environment (AWS_REGION / profile)."
  type        = string
  default     = null
}

variable "name" {
  description = "Unique identifier for policy naming. Must be unique per AWS account (IAM policy names are account-global). Example: \"prod-us-east-1\"."
  type        = string
}

variable "create_role" {
  description = "When true, creates a new IAM role and attaches all policies to it. The role will allow the ARNs in trusted_arns to assume it via sts:AssumeRole."
  type        = bool
  default     = false
}

variable "role_name" {
  description = "Existing IAM role name to attach the Lambda policies to. Ignored when create_role is true."
  type        = string
  default     = null
}

variable "trusted_arns" {
  description = "List of IAM principal ARNs allowed to assume the role. Only used when create_role is true."
  type        = list(string)
  default     = []
}
