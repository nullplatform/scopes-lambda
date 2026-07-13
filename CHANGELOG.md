# Changelog

## [0.1.0](https://github.com/nullplatform/scopes-lambda/compare/0.0.1...v0.1.0) (2026-07-13)


### Features

* add dynamic assume role support via scope-configurations provider ([085964a](https://github.com/nullplatform/scopes-lambda/commit/085964ac38c51559cf583e68469cc20c750d4962))
* add OpenTofu installation setup for Lambda scope ([#4](https://github.com/nullplatform/scopes-lambda/issues/4)) ([3439713](https://github.com/nullplatform/scopes-lambda/commit/343971373056cafe8dcf0e28991fce31b5beb058))
* add permissions boundary support to Lambda execution role ([#10](https://github.com/nullplatform/scopes-lambda/issues/10)) ([f4d893b](https://github.com/nullplatform/scopes-lambda/commit/f4d893b6c2dd761e703e6924f1e30a1d1e0815fa))
* add requirements module with IAM policies for Lambda scope operations ([d9ff61b](https://github.com/nullplatform/scopes-lambda/commit/d9ff61bbf712c2c39ea3479338aef5bf1afb88c7))
* adjust configuration ([#8](https://github.com/nullplatform/scopes-lambda/issues/8)) ([edecc50](https://github.com/nullplatform/scopes-lambda/commit/edecc502a1bfd0fa022c75212fe70a50a7ac472b))
* adjust configuration ([#9](https://github.com/nullplatform/scopes-lambda/issues/9)) ([47c2c57](https://github.com/nullplatform/scopes-lambda/commit/47c2c57e0cab77baf9780a7749c91362ab322983))
* adjust values ([#7](https://github.com/nullplatform/scopes-lambda/issues/7)) ([425d397](https://github.com/nullplatform/scopes-lambda/commit/425d397d1a418889f42b62c75ff3a67d00d07719))
* asset types support ([#3](https://github.com/nullplatform/scopes-lambda/issues/3)) ([6f58a3a](https://github.com/nullplatform/scopes-lambda/commit/6f58a3a5cebb9971f8a5a63e1d072049e2edca8b))
* **assume-role:** resolve role ARN from nullplatform IAM provider by selector ([779eef9](https://github.com/nullplatform/scopes-lambda/commit/779eef99afc7b328103b3b3b665c10b64d2efe97))
* dynamic assume-role support, configurable placeholder image & install tofu consolidation ([847e5fd](https://github.com/nullplatform/scopes-lambda/commit/847e5fd85650dedeac5b2db07caa9dc83117527b))
* **iam:** make Lambda execution-role prefix configurable ([23e2515](https://github.com/nullplatform/scopes-lambda/commit/23e25154a706e45f6101b23ff5561f7555e97123))
* implement entrypoints and base configuration for specs ([b34586f](https://github.com/nullplatform/scopes-lambda/commit/b34586f15daeac56c1f1c4ecd02757cfecb5dc3f))
* **install/specs:** add scope-configuration.json.tpl ([e39b5bf](https://github.com/nullplatform/scopes-lambda/commit/e39b5bfd24e956917327d8625d7f44401ece6b78))
* **install/specs:** add scope-configuration.json.tpl ([e25024b](https://github.com/nullplatform/scopes-lambda/commit/e25024b0d2be49c448dda25e28d9008f968a4600))
* **lambda:** optional public ALB in requirements module ([#30](https://github.com/nullplatform/scopes-lambda/issues/30)) ([fae610e](https://github.com/nullplatform/scopes-lambda/commit/fae610ebcd058165a093763775d99d9859ba1f76))
* **placeholder:** make placeholder image configurable via PLACEHOLDER_IMAGE_URI_DEFAULT ([bd26af4](https://github.com/nullplatform/scopes-lambda/commit/bd26af424b97875ca50fbc16da8a0d06753f3ce6))
* tofu refactor ([#13](https://github.com/nullplatform/scopes-lambda/issues/13)) ([e753833](https://github.com/nullplatform/scopes-lambda/commit/e753833c283daec0df57ee51feae64412226138e))
* **workflows:** assume IAM role via dedicated first step in every workflow ([5109c0e](https://github.com/nullplatform/scopes-lambda/commit/5109c0ef721f5128580bc8ba545658cb380e3fa8))


### Bug Fixes

* correct nullplatform provider version constraint in specs/tofu ([d49d2b9](https://github.com/nullplatform/scopes-lambda/commit/d49d2b983a2db8bd980a92173a2fd865316ee6a1))
* **deploy:** add missing diagnose.yaml workflow for diagnose-deployment action ([c04e9cc](https://github.com/nullplatform/scopes-lambda/commit/c04e9cc67aaa1f4de47fda2630417d7f51cb87db))
* **deploy:** ensure Lambda pull policy on the image's ECR repo before update ([2dc0a3e](https://github.com/nullplatform/scopes-lambda/commit/2dc0a3ef0836d525000998870cf106682ad01784))
* **iam:** add modern CloudWatch Logs tagging actions to lambda requirements policy ([b9e41d3](https://github.com/nullplatform/scopes-lambda/commit/b9e41d3bfdde1586a6f89cbb61e3b76b8a203ac2))
* **iam:** prefix lambda execution role with np-lambda- to match requirements policy ([97121e4](https://github.com/nullplatform/scopes-lambda/commit/97121e48ce48a57544fab74f987c213e2b61a1e3))
* parameters ([#12](https://github.com/nullplatform/scopes-lambda/issues/12)) ([c63f0c1](https://github.com/nullplatform/scopes-lambda/commit/c63f0c16b1335f20ade3795105ebadd7aff05d84))
* permissions boundary and least-privilege IAM for Lambda scope ([#11](https://github.com/nullplatform/scopes-lambda/issues/11)) ([47e50d0](https://github.com/nullplatform/scopes-lambda/commit/47e50d005e498a3dfdb9f984d4486513e250c1e8))
* **publish:** remove hardcoded `--profile kwik` from ECR setup calls ([b076628](https://github.com/nullplatform/scopes-lambda/commit/b076628b97096fa87b8104a59d66c35fe2f8381d))
* **publish:** remove hardcoded `--profile kwik` from ECR setup calls ([cfc6e87](https://github.com/nullplatform/scopes-lambda/commit/cfc6e8757f6175577cdb0346170ffe9d35018d09))
* read TOFU_STATE_BUCKET from .provider.aws_state_bucket as fallback ([3f89288](https://github.com/nullplatform/scopes-lambda/commit/3f89288f8b0246beb6011658249c6ef65e904d2a))
* remove automatic arch suffix from placeholder image URI ([fc8bc76](https://github.com/nullplatform/scopes-lambda/commit/fc8bc760f83316b69a07fb2eb3c32feb91da02c5))
* **specs/tofu:** bump aws provider constraint to ~&gt; 6.47.0 ([6752bee](https://github.com/nullplatform/scopes-lambda/commit/6752beefd4ebc313c936efd46c8d3e027b4022fe))
* **specs:** derive asset_type from deployment_type ([fa34054](https://github.com/nullplatform/scopes-lambda/commit/fa34054828af58dd6e6e0ba4bbd41628b8f5ca71))
* surface sts:AssumeRole errors to stdout for visibility in NP logs ([33842ec](https://github.com/nullplatform/scopes-lambda/commit/33842ec3194eee25162bddc5669cd0035a18bcd7))
* **tofu:** surface tofu apply stderr to stdout for visibility in NP logs ([684d9f7](https://github.com/nullplatform/scopes-lambda/commit/684d9f7fd5aab98a2686e55901fa62b27db9a9a1))
* use exact PLACEHOLDER_IMAGE_URI when explicitly set, skip arch suffix ([14d3ad5](https://github.com/nullplatform/scopes-lambda/commit/14d3ad54b4ee082c44037b4b1f746f0b45c35705))
