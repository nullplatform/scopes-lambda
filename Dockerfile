# syntax=docker/dockerfile:1
#
# scopes-lambda worker image — self-contained. Stage 1 compiles the nullplatform
# worker gRPC bridge (vendored from plugin-base-worker under worker-base/); stage
# 2 assembles a lean runtime with the Lambda toolchain (aws CLI + OpenTofu) and
# the scope code. The bridge runs lambda/entrypoint per package-exec command, so
# the package-exec channel needs no cmdline.
#
#   docker build --platform linux/amd64 -t public.ecr.aws/nullplatform/scopes:lambda-0.0.1 .

# ── stage 1: compile the bridge to a static musl binary ──────────────────
FROM oven/bun:1-alpine AS bridge
WORKDIR /w
COPY worker-base/package.json worker-base/bun.lock* ./
RUN bun install
COPY worker-base/src ./src
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then t=bun-linux-arm64-musl; else t=bun-linux-x64-musl; fi; \
    bun build --compile --target="$t" ./src/index.ts --outfile /w/worker

# ── stage 2: lambda worker runtime ───────────────────────────────────────
FROM alpine:3.20
# bridge deps (libstdc++/libgcc) + entrypoint toolchain (bash/jq/curl/np CLI) +
# Lambda-specific tools (aws CLI, OpenTofu). The base stays minimal; these live
# here because they are what the Lambda scope's scripts actually call.
RUN apk add --no-cache libstdc++ libgcc bash jq curl ca-certificates openssl aws-cli
RUN curl -sSL https://cli.nullplatform.com/install.sh | sh
ARG TOFU_VERSION=1.10.6
RUN arch="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" \
 && curl -sSL "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${arch}.tar.gz" \
      | tar -xz -C /usr/local/bin tofu

COPY --from=bridge /w/worker /usr/local/bin/worker
COPY worker-base/config /app/worker/config
COPY lambda /app/pkg/lambda

ENV NODE_CONFIG_DIR=/app/worker/config \
    SUPPRESS_NO_CONFIG_WARNING=1 \
    NP_AGENT_PLUGIN=np-agent-v1 \
    PATH=/root/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    NP_SERVICE_PATH=/app/pkg/lambda \
    NP_SCOPE_ENTRYPOINT=/app/pkg/lambda/entrypoint \
    NP_PACKAGE_NAME=scopes-lambda \
    NP_PACKAGE_VERSION=0.0.2

EXPOSE 50051
ENTRYPOINT ["worker"]
