# syntax=docker/dockerfile:1
#
# scopes-lambda worker image — the AWS Lambda scope built on the lean gRPC
# worker bridge. The bridge dials over gRPC and runs the bash entrypoint on each
# package-exec action; this image adds the cloud tooling the lambda steps need
# and bakes the scope in, so the package-exec channel needs no cmdline.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

# Cloud tooling the lambda steps call (the bridge base stays minimal on purpose):
# aws + opentofu (tofu) + gomplate. bash, jq, np, base64 and curl ship in the base.
RUN apk add --no-cache aws-cli opentofu gomplate

# Bake the scope in and point the bridge at the lambda entrypoint + service path.
COPY . /app/pkg
ENV NP_PACKAGE_NAME=scopes-lambda \
    NP_SERVICE_PATH=/app/pkg/lambda \
    NP_SCOPE_ENTRYPOINT=/app/pkg/lambda/entrypoint
