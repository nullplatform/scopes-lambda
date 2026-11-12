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
# organization that installs the package, which creates them with tofu-modules'
# scope_package_installation; the publisher organization would only get unused copies.
#
# Run only by the release workflow, through actions-nullplatform's
# publish-package (see release.yml).
################################################################################

locals {
  # The np- prefix keeps the global package and its specification apart from
  # what organizations registered from this repository with specs/install:
  # their own package scopes-lambda and specification "AWS Lambda" (slug
  # aws-lambda). Package lookups and agent channels match by slug, so the two
  # must differ for both to live in one organization. The prefix lives in the
  # slug only: the specification keeps the plain name people read.
  package_slug = "np-aws-lambda"
  service_path = "lambda"
  # The release tag the workflow passes, as the artifact registration takes it.
  # The guard below refuses to publish without one.
  version = var.release_tag == null ? null : trimprefix(var.release_tag, "v")

  # Whether this revision becomes the package default — what an organization
  # that installs without pinning a version is born with. A stable release
  # promotes; a prerelease (any semver with a `-`, such as 0.12.0-rc.1) is
  # published without moving the default. promote_default forces either.
  promote_default = (
    var.promote_default != null ? var.promote_default :
    local.version == null ? false :
    length(regexall("-", local.version)) == 0
  )
}

# A revision without a tag would have no version.
resource "terraform_data" "release_guard" {
  lifecycle {
    precondition {
      condition     = var.release_tag != null
      error_message = "release_tag is required: it is the package revision's version."
    }
  }
}

module "scope_definition" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition?ref=v9.12.0"

  nrn = var.publisher_nrn

  # Templates come from this checkout (the release workflow applies the stack
  # at the release tag), so the package pins exactly the specs of its release.
  local_specs_path = abspath("${path.module}/..")
  service_path     = local.service_path

  # The name is what people read; the slug carries the namespace and is what
  # the installation's channel filter and NRN settings use. The package the
  # module publishes takes the specification's slug.
  service_spec_name        = "AWS Lambda"
  service_spec_slug        = local.package_slug
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

  # Each installing organization creates these (scope_package_installation), and without
  # the NRN patch the apply needs no `np`.
  create_scope_type          = false
  configure_nrn_settings     = false
  create_scope_configuration = false

  package = {
    slug       = local.package_slug
    version    = local.version
    default    = local.promote_default
    visible_to = ["organization=*"]
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
