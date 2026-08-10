# syntax=docker/dockerfile:1
#
# scopes-lambda worker image — the AWS Lambda scope built on the lean gRPC
# worker bridge. The bridge dials over gRPC and runs the bash entrypoint on each
# package-exec action; this image adds the cloud tooling the lambda steps need
# and bakes the scope in, so the package-exec channel needs no cmdline.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

# Cloud tooling the lambda steps call (the bridge base stays minimal on purpose):
# aws + gomplate from apk. bash, jq, np, base64 and curl ship in the base.
RUN apk add --no-cache aws-cli gomplate

# OpenTofu >= 1.10 — the scope inits its S3 backend with use_lockfile=true
# (lambda/scope/tofu/provider/aws/setup), which needs tofu 1.10+. alpine 3.20
# only packages 1.7.2, so pull the official static binary for the build arch.
ARG TOFU_VERSION=1.10.6
ARG TARGETARCH
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin tofu \
    && tofu version

# Bake the scope in and point the bridge at the lambda entrypoint + service path.
COPY . /app/pkg
ENV NP_PACKAGE_NAME=scopes-lambda \
    NP_SERVICE_PATH=/app/pkg/lambda \
    NP_SCOPE_ENTRYPOINT=/app/pkg/lambda/entrypoint
