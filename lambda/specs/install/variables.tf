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
# Worker model
#
# The agent spawns the released worker image per action instead of git-cloning
# this repo. Requires a worker-orchestrator agent listening on tags_selectors,
# allowing public.ecr.aws/nullplatform/scopes*.
################################################################################

variable "worker_orchestrator" {
  description = "Publish the scope as a package and emit a package-exec channel. False keeps the git-clone exec channel."
  type        = bool
  default     = true
}

variable "package_slug" {
  description = "Slug of the scope package"
  type        = string
  default     = "scopes-lambda"
}

variable "package_version" {
  description = "Semver of the package revision to publish. Bump when pinning a newer worker image."
  type        = string
  default     = "0.0.1"
}

variable "worker_image_digest" {
  description = "Digest of the worker image to pin. Taken from the Artifact table of the matching GitHub release."
  type        = string
  # v0.3.2
  default = "sha256:4151e8005a6ad7de44b82411cf4f04cf197cf52d4a399e403ffdcd111e083482"
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
