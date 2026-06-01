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
