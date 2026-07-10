variable "agent_role_arn" {
  description = "ARN of the primary nullplatform agent IRSA role allowed to assume this Lambda permissions role via sts:AssumeRole, and always a trusted principal of the role's trust policy. Defaults (when empty) to the conventional agent role for the cluster: arn:aws:iam::<account>:role/nullplatform-<cluster_name>-agent-role."
  type        = string
  default     = ""

  validation {
    condition     = var.agent_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.agent_role_arn))
    error_message = "agent_role_arn must be empty (to use the derived default) or match arn:aws:iam::<account-id>:role/<role-name>"
  }
}

variable "additional_agent_role_arns" {
  description = "Extra IAM role ARNs allowed to assume this permissions role, appended to agent_role_arn in the trust policy. Defaults to none."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.additional_agent_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/.+", arn))])
    error_message = "each additional_agent_role_arns entry must match arn:aws:iam::<account-id>:role/<role-name>"
  }
}

variable "cluster_name" {
  description = "Name of the cluster where the agent runs. Used to derive default resource names."
  type        = string
}

variable "role_name" {
  description = "Override for the Lambda permissions IAM role name. Defaults to nullplatform_{cluster_name}_lambda_role."
  type        = string
  default     = ""
}

variable "policies_name_prefix" {
  description = "Override for the IAM policy name prefix. Defaults to nullplatform_{cluster_name}."
  type        = string
  default     = ""
}

variable "iam_create_role" {
  description = "Whether to create the permissions role, its policies and the placeholder ECR repository. When false, the module produces no resources."
  type        = bool
  default     = true
}

variable "iam_resource_tags_json" {
  description = "Tags to apply to IAM resources created by this module."
  type        = map(string)
  default     = {}
}

variable "placeholder_repository_name" {
  description = "Name of the private ECR repository holding the Lambda placeholder image. Lambda container functions bootstrap from this image until the first real deployment."
  type        = string
  default     = "aws-lambda/nullplatform-lambda-placeholder"
}

variable "assets_bucket_name" {
  description = "Name of the S3 bucket holding Lambda deployment assets (read access granted to the permissions role in the storage policy)."
  type        = string
  default     = "lambda-files-aws-services"
}

# --- Optional public ALB for Lambda HTTP exposure ---------------------------

variable "install_alb" {
  description = "When true, create a dedicated public ALB (+ HTTPS/HTTP listeners + SG) for exposing Lambda functions over HTTP. Off by default so IAM-only consumers are unaffected."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC where the Lambda ALB is created. Required when install_alb = true."
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the ALB. When empty and install_alb = true, subnets are discovered by the nullplatform/subnet-type=public tag on vpc_id."
  type        = list(string)
  default     = []
}

variable "public_zone_id" {
  description = "Route53 public hosted zone ID used to DNS-validate the wildcard certificate. Required when install_alb = true and certificate_arn is empty."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Base domain for the wildcard certificate (*.<domain_name>). Required when install_alb = true and certificate_arn is empty."
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "Existing ACM wildcard certificate ARN to reuse for the ALB HTTPS listener. When empty and install_alb = true, a wildcard cert is created from domain_name + public_zone_id."
  type        = string
  default     = ""
}

variable "alb_name" {
  description = "Override for the ALB name (max 32 chars). Defaults to np-{cluster_name}-lambda."
  type        = string
  default     = ""
}
