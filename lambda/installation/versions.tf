terraform {
  required_version = ">= 1.6"

  required_providers {
    nullplatform = {
      source = "nullplatform/nullplatform"
      # nullplatform_package_installation, data.nullplatform_package.visible_at
      # and .components: the first provider release after 0.0.109.
      version = ">= 0.0.110"
    }
  }
}

# The release this module installs: the tag you reference it at. release-please
# (release-type terraform-module) rewrites it in the release PR; keep it the
# only vX.Y.Z in this file.
locals {
  release = "v0.11.1"
}
