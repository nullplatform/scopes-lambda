# scopes-lambda publish

OpenTofu stack that publishes this scope as the package `scopes-lambda`, visible to every organization. Only the `publish-package` job of [`release.yml`](../../.github/workflows/release.yml) runs it; organizations install the package with [`../installation`](../installation).

Each apply publishes one immutable revision that pins:

- the scope specification and every action specification, rendered from the templates of the release tag (read from raw GitHub at that tag);
- the worker image the same release pushed, by digest.

The revision's version is `local.release` in [`versions.tf`](./versions.tf), which release-please rewrites in every release PR. The job refuses to run when it does not match the release tag. Re-applying the same release is a no-op.

The `scope_definition` module also creates a scope type, NRN settings and the scope-configuration schema in the publisher organization. Those serve only that organization; every other organization gets its own from the installation module.

## Repository configuration

| Kind | Name | Purpose |
|---|---|---|
| secret | `PACKAGE_NP_API_KEY` | API key of the publisher organization, allowed to write specs, scope types, provider specifications and packages |
| secret | `AWS_ROLE_ARN_PUBLISH_STATE` | OIDC role with access to the state bucket |
| variable | `PUBLISH_TFSTATE_BUCKET` | S3 bucket for this stack's state. The job is skipped while it is unset |
| variable | `PUBLISH_TFSTATE_REGION` | Region of that bucket |
| variable | `NP_ARTIFACT_NRN` | Publisher organization NRN (already used to register the image) |

The job installs `gomplate` and `np`, which the module uses to render the templates and patch the NRN.
