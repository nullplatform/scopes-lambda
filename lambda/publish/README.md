# scopes-lambda publish

OpenTofu stack that publishes this scope as the package `scopes-lambda`, visible to every organization. Only the release workflow runs it, through the shared [`publish-package`](https://github.com/nullplatform/actions-nullplatform#publish-package) workflow that [`release.yml`](../../.github/workflows/release.yml) enables with `package_stack_dir`; organizations install the package with [`../installation`](../installation).

Each apply publishes one immutable revision that pins:

- the scope specification and every action specification, rendered from the templates of the release tag (read from the checkout the workflow applies the stack in);
- the worker image the same release pushed, by digest.

The revision's version is `local.release` in [`versions.tf`](./versions.tf), which release-please rewrites in every release PR. The apply refuses to publish when it does not match the release tag (`release_tag`, set by the workflow). Re-applying the same release is a no-op.

The `scope_definition` module also creates a scope type, NRN settings and the scope-configuration schema in the publisher organization. Those serve only that organization; every other organization gets its own from the installation module.

## Repository configuration

| Kind | Name | Purpose |
|---|---|---|
| secret | `PACKAGE_NP_API_KEY` | API key of the publisher organization, allowed to write specs, scope types, provider specifications and packages |
| secret | `AWS_ROLE_ARN_PACKAGE_STATE` | OIDC role with access to the state bucket |
| variable | `PACKAGE_TFSTATE_BUCKET` | S3 bucket for package stack states (can be set once for the organization). Publishing is skipped while it is unset |
| variable | `PACKAGE_TFSTATE_REGION` | Region of that bucket |
| variable | `NP_ARTIFACT_NRN` | Publisher organization NRN (already used to register the image) |

`release.yml` asks the workflow for `gomplate` and `np` (`package_tools`), which the module uses to render the templates and patch the NRN.
