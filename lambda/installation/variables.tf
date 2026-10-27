variable "nrn" {
  description = "NRN of your organization where the scope is installed (e.g. organization=123:account=456). The package is looked up as visible there, and the installation, scope type, NRN settings, scope-configuration schema and agent channel are created there."
  type        = string
}

variable "visible_to" {
  description = "Where inside your organization the scope can be used. Defaults to [nrn]. Every entry must be under your organization."
  type        = list(string)
  default     = null
}

variable "agent_tags_selectors" {
  description = "Tags that select the agent running this scope (must match the agent's TAGS), e.g. { cluster = \"runtime\" }."
  type        = map(string)
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
  description = "Name of the scope type developers pick. Null uses the template's (\"AWS Lambda\"); override it when your organization already has a scope type with that name, registered with specs/install."
  type        = string
  default     = null
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

# --- AWS (../specs/requirements) ----------------------------------------------

variable "cluster_name" {
  description = "Name of the cluster where the agent runs. Names the IAM role, policies and ALB."
  type        = string
}

variable "agent_role_arn" {
  description = "ARN of the agent's IAM role, trusted by the scope's permissions role. Empty uses the conventional arn:aws:iam::<account>:role/nullplatform-<cluster_name>-agent-role."
  type        = string
  default     = ""
}

variable "additional_agent_role_arns" {
  description = "Extra IAM role ARNs allowed to assume the scope's permissions role."
  type        = list(string)
  default     = []
}

variable "iam_create_role" {
  description = "Create the IAM permissions role, its policies and the placeholder ECR repository. Set to false when your stack already manages them."
  type        = bool
  default     = true
}

variable "iam_role_name" {
  description = "Name of the IAM permissions role. Empty uses nullplatform_<cluster_name>_lambda_role."
  type        = string
  default     = ""
}

variable "iam_policies_name_prefix" {
  description = "Prefix of the IAM policy names. Empty uses nullplatform_<cluster_name>."
  type        = string
  default     = ""
}

variable "iam_resource_tags" {
  description = "Tags added to every IAM resource."
  type        = map(string)
  default     = {}
}

variable "placeholder_repository_name" {
  description = "Private ECR repository holding the Lambda placeholder image."
  type        = string
  default     = "aws-lambda/nullplatform-lambda-placeholder"
}

variable "assets_bucket_name" {
  description = "S3 bucket holding Lambda deployment assets (read access granted to the permissions role)."
  type        = string
  default     = "lambda-files-aws-services"
}

variable "install_alb" {
  description = "Create a dedicated public ALB to expose Lambda functions over HTTP."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC of the ALB. Required when install_alb = true."
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "Public subnets of the ALB. Empty discovers them by the nullplatform/subnet-type=public tag on vpc_id."
  type        = list(string)
  default     = []
}

variable "public_zone_id" {
  description = "Route53 public zone that validates the wildcard certificate. Required when install_alb = true and certificate_arn is empty."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Base domain of the wildcard certificate. Required when install_alb = true and certificate_arn is empty."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "Existing ACM wildcard certificate for the ALB. Empty creates one from domain_name."
  type        = string
  default     = ""
}

variable "alb_name" {
  description = "Name of the ALB (max 32 chars). Empty uses np-<cluster_name>-lambda."
  type        = string
  default     = ""
}
