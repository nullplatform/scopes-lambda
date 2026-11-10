terraform {
  required_version = ">= 1.6"

  # Partial configuration: bucket, key and region come from -backend-config in
  # the release workflow, so no account detail lives in the repository.
  backend "s3" {}

  required_providers {
    nullplatform = {
      source = "nullplatform/nullplatform"
      # 0.0.113 takes `slug` on nullplatform_service_specification.
      version = ">= 0.0.113"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# The release this stack publishes. release-please (release-type
# terraform-module) rewrites it in the release PR; keep it the only vX.Y.Z in
# this file.
locals {
  release = "v0.13.1"
}

# Credentials come from NULLPLATFORM_API_KEY: a key of the publisher
# organization, the only one allowed to publish with organization=* visibility.
provider "nullplatform" {}
