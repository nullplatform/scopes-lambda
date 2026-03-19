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
