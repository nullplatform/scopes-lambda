variable "publisher_nrn" {
  description = "Owner NRN of the package: the publisher organization (e.g. organization=123). The service spec, action specs and package are created here."
  type        = string
}

variable "release_tag" {
  description = "Release tag being published (vX.Y.Z, or vX.Y.Z-<pre> for a prerelease), set by the release workflow. It is the revision's version, without the v."
  type        = string
  default     = null

  validation {
    condition     = var.release_tag == null || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?$", var.release_tag))
    error_message = "release_tag must look like vX.Y.Z or vX.Y.Z-<prerelease>."
  }
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

variable "promote_default" {
  description = "Whether the published revision becomes the package default. Null (the default) promotes a stable release and leaves a prerelease (a version with a `-`) where it is; true or false forces it."
  type        = bool
  default     = null
}
