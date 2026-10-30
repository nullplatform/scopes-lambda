################################################################################
# scopes-lambda — publisher stack
#
# Publishes the scope as ONE package visible to every organization
# (organization=*): the service spec and every action spec rendered from the
# templates of the release tag, plus the worker image the same release pushed,
# pinned by digest. Each release publishes a new immutable revision; re-applying
# the same release is a no-op.
#
# Only what the package pins is created in the publisher organization. The
# scope type, NRN settings and scope-configuration schema belong to each
# organization that installs the package, which creates them with
# ../installation; the publisher organization would only get unused copies.
#
# Run only by the release workflow, through actions-nullplatform's
# publish-package (see release.yml).
################################################################################

locals {
  # The nullplatform- prefix keeps the global package and its specification
  # apart from what organizations registered from this repository with
  # specs/install: their own package scopes-lambda and specification
  # "AWS Lambda" (slug aws-lambda). Package lookups and agent channels match by
  # slug, so the two must differ for both to live in one organization.
  package_slug = "nullplatform-aws-lambda"
  version      = trimprefix(local.release, "v")
  service_path = "lambda"
}

# Publishing other templates under this version would break its immutability.
resource "terraform_data" "release_guard" {
  lifecycle {
    precondition {
      condition     = var.release_tag == null || var.release_tag == local.release
      error_message = "versions.tf releases ${local.release} but the release tag is ${coalesce(var.release_tag, "unset")}."
    }
  }
}

module "scope_definition" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition?ref=v9.7.0"

  nrn = var.publisher_nrn

  # Templates come from this checkout (the release workflow applies the stack
  # at the release tag), so the package pins exactly the specs of its release.
  local_specs_path = abspath("${path.module}/..")
  service_path     = local.service_path

  # Slugifies to the package slug, the specification slug the installation's
  # channel filter and NRN settings use.
  service_spec_name        = "nullplatform AWS Lambda"
  service_spec_description = "AWS Lambda functions managed by nullplatform"

  action_spec_names = [
    "adjust-provisioned-concurrency",
    "adjust-reserved-concurrency",
    "create-scope",
    "delete-deployment",
    "delete-scope",
    "diagnose-deployment",
    "diagnose-scope",
    "finalize-blue-green",
    "invoke",
    "rollback-deployment",
    "start-blue-green",
    "start-initial",
    "switch-traffic",
    "update-scope",
  ]

  # Each installing organization creates these (../installation), and without
  # the NRN patch the apply needs no `np`.
  create_scope_type          = false
  configure_nrn_settings     = false
  create_scope_configuration = false

  package = {
    slug       = local.package_slug
    version    = local.version
    visible_to = ["organization=*"]
    # No requires_providers: the API does not accept the declaration yet, and
    # organizations that create their providers in a layer applied after the
    # install could never satisfy a required one. The scope checks its providers
    # at runtime, as it always did.
    artifacts = [{
      name   = "worker-image"
      lookup = true # registered by the release workflow before this runs
      meta = {
        registry   = var.image_registry
        repository = var.image_repository
        digest     = var.image_digest
      }
    }]
  }
}
