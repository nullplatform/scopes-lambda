variable "iam_role_name" {
  description = "Name of the IAM role"
  type        = string
  default     = ""
}

variable "iam_create_role" {
  description = "Whether to create the IAM role"
  type        = bool
  default     = false
}

variable "iam_role_policies" {
  description = "List of IAM policies to attach"
  type = list(object({
    name   = string
    policy = string
  }))
  default = []
}

variable "iam_vpc_enabled" {
  description = "Whether Lambda needs VPC access"
  type        = bool
  default     = false
}

variable "iam_role_entity" {
  description = "Role entity type (scope or deployment)"
  type        = string
  default     = "scope"
}

variable "iam_resource_tags_json" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}

variable "iam_secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN for parameters (empty to disable)"
  type        = string
  default     = ""
}

variable "lambda_role_arn" {
  description = "Existing Lambda role ARN (when not creating)"
  type        = string
  default     = ""
}

variable "iam_package_type" {
  description = "Lambda deployment package type (Zip or Image) - used to add ECR pull permissions for image deployments"
  type        = string
  default     = "Zip"
}

variable "iam_propagation_duration" {
  description = "How long to wait after IAM role creation for global propagation (e.g. '20s'). Only fires on initial role creation."
  type        = string
  default     = "0s"
}

variable "iam_scope_id" {
  description = "Scope ID used to scope the Secrets Manager wildcard policy when creating the role"
  type        = string
  default     = ""
}

variable "iam_permissions_boundary" {
  description = "ARN of the IAM permissions boundary to attach to the Lambda execution role (empty to disable)"
  type        = string
  default     = ""
}
