variable "publisher_nrn" {
  description = "Owner NRN of the package: the publisher organization (e.g. organization=123). The specs, action specs, scope type and scope-configuration schema are created here."
  type        = string
}

variable "np_api_key" {
  description = "Publisher organization API key, used by the scope_definition module's local `np nrn patch`."
  type        = string
  sensitive   = true
}

variable "image_digest" {
  description = "Digest of the worker image this release pushed (sha256:<64 hex>). Pins the package revision to that exact image."
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.image_digest))
    error_message = "image_digest must look like sha256:<64 hex chars>."
  }
}

variable "image_registry" {
  description = "Registry host of the worker image."
  type        = string
  default     = "public.ecr.aws"
}

variable "image_repository" {
  description = "Repository of the worker image inside the registry."
  type        = string
  default     = "nullplatform/scopes/lambda"
}
