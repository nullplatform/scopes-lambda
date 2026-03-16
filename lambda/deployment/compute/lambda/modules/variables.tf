variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "nodejs20.x"
}

variable "lambda_handler" {
  description = "Function entrypoint"
  type        = string
  default     = "index.handler"
}

variable "lambda_memory_size" {
  description = "Amount of memory in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout" {
  description = "Function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_ephemeral_storage" {
  description = "Ephemeral storage size in MB"
  type        = number
  default     = 512
}

variable "lambda_architecture" {
  description = "Instruction set architecture (arm64 or x86_64)"
  type        = string
  default     = "arm64"
}

variable "lambda_package_type" {
  description = "Lambda deployment package type (Zip or Image)"
  type        = string
  default     = "Zip"
}

variable "lambda_image_uri" {
  description = "ECR image URI for container image deployments"
  type        = string
  default     = ""
}

variable "lambda_s3_bucket" {
  description = "S3 bucket containing the deployment package"
  type        = string
  default     = ""
}

variable "lambda_s3_key" {
  description = "S3 key of the deployment package"
  type        = string
  default     = ""
}

variable "lambda_environment_variables" {
  description = "Environment variables for the function"
  type        = map(string)
  default     = {}
}

variable "lambda_layers" {
  description = "List of Lambda layer ARNs"
  type        = list(string)
  default     = []
}

variable "lambda_vpc_config" {
  description = "VPC configuration for Lambda"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "lambda_reserved_concurrency_type" {
  description = "Reserved concurrency type (unreserved or reserved)"
  type        = string
  default     = "unreserved"
}

variable "lambda_reserved_concurrency_value" {
  description = "Number of reserved concurrent executions"
  type        = number
  default     = -1
}

variable "lambda_provisioned_concurrency_type" {
  description = "Provisioned concurrency type (unprovisioned or provisioned)"
  type        = string
  default     = "unprovisioned"
}

variable "lambda_provisioned_concurrency_value" {
  description = "Number of provisioned concurrent executions"
  type        = number
  default     = 0
}

variable "lambda_main_alias_name" {
  description = "Name of the main alias for traffic routing"
  type        = string
  default     = "main"
}

variable "lambda_warmup_alias_name" {
  description = "Name of the warmup alias (empty to disable)"
  type        = string
  default     = ""
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "lambda_tags" {
  description = "Tags to apply to Lambda resources"
  type        = map(string)
  default     = {}
}

variable "lambda_publish" {
  description = "Whether to publish a new Lambda version"
  type        = bool
  default     = true
}

variable "lambda_description" {
  description = "Description embedded in each published version; used to look up the version by deployment ID"
  type        = string
  default     = ""
}
