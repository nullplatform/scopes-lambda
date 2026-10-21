################################################################################
# scopes-lambda — publisher stack
#
# Publishes the scope as ONE package visible to every organization
# (organization=*): the service spec and every action spec rendered from the
# templates of the release tag, plus the worker image the same release pushed,
# pinned by digest. Each release publishes a new immutable revision; re-applying
# the same release is a no-op.
#
# The scope type, NRN settings and scope-configuration schema this module also
# creates belong to the publisher organization only. Every other organization
# gets its own from ../installation.
#
# Run only by the release workflow, through actions-nullplatform's
# publish-package (see release.yml).
################################################################################

locals {
  package_slug = "scopes-lambda"
  version      = trimprefix(local.release, "v")
  service_path = "lambda"

  # Templates are read from raw GitHub at the release tag, so the package pins
  # exactly the specs of its own release (the repository is public).
  templates_url = "https://raw.githubusercontent.com/nullplatform/scopes-lambda/refs/tags"
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
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition?ref=v9.4.0"

  nrn        = var.publisher_nrn
  np_api_key = var.np_api_key

  service_path = local.service_path

  repository_service_spec            = local.templates_url
  repository_service_spec_branch     = local.release
  repository_scope_template          = local.templates_url
  repository_scope_template_branch   = local.release
  repository_action_templates        = local.templates_url
  repository_action_templates_branch = local.release

  service_spec_name        = "AWS Lambda"
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

  create_scope_configuration = true

  package = {
    slug       = local.package_slug
    version    = local.version
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
