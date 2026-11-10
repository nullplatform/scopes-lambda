# scopes-lambda publish

OpenTofu stack that publishes this scope as the package `np-aws-lambda` (specification "AWS Lambda"), visible to every organization. Only the release workflow runs it, through the shared [`publish-package`](https://github.com/nullplatform/actions-nullplatform#publish-package) workflow that [`release.yml`](../../.github/workflows/release.yml) enables with `package_stack_dir`; organizations install the package with [`../installation`](../installation).

Each apply publishes one immutable revision that pins:

- the scope specification and every action specification, rendered from the templates of the release tag (read from the checkout the workflow applies the stack in);
- the worker image the same release pushed, by digest.

The revision's version is `local.release` in [`versions.tf`](./versions.tf), which release-please rewrites in every release PR. The apply refuses to publish when it does not match the release tag (`release_tag`, set by the workflow). Re-applying the same release is a no-op.

Only what the package pins is created in the publisher organization: the service specification, its action specifications and the package. The scope type, NRN settings and scope-configuration schema are created by each organization that installs the package, with tofu-modules' `scope_package_installation`, so the stack turns them off in `scope_definition` (`create_scope_type`, `configure_nrn_settings` and `create_scope_configuration` set to `false`).

## Which revision becomes the default

Not every publish moves the package default, the revision an organization that installs without pinning a version is born with. A stable release promotes itself; a prerelease (any version with a `-`, such as `0.12.0-rc.1`) is published without moving the default, so it can be installed by version to try it. `promote_default` (`-var promote_default=false`, or `true`) forces either way.

## Repository configuration

| Kind | Name | Purpose |
|---|---|---|
| secret | `ARTIFACT_NP_API_KEY` | API key of the publisher organization, already used to register the image. Passed as `package_np_api_key`, so it must also be allowed to write specs and packages |
| secret | `AWS_ROLE_ARN_PACKAGE_STATE` | OIDC role with access to the state bucket |
| secret | `PACKAGE_TFSTATE_BUCKET` | S3 bucket for package stack states. Publishing is skipped while it is unset. A secret, not a variable: this repository is public and so are its run logs, and GitHub masks only secrets |
| secret | `PACKAGE_TFSTATE_REGION` | Region of that bucket, a secret for the same reason |
| variable | `NP_ARTIFACT_NRN` | Publisher organization NRN (already used to register the image) |

`release.yml` asks the workflow for `gomplate` (`package_tools`), which the module uses to render the templates.
