# The lambda-v2 worker image: the scope provider host with the AWS provider the program declares,
# plus this package itself, which the agent runs for the telemetry data actions (`log:read`,
# `metric:*`) through its `package-exec` command: `/app/packages/lambda-v2/entrypoint` with the
# notification in NP_ACTION_CONTEXT.
#
#   docker build --build-arg PROVIDER_HOST_IMAGE=scope-provider-host:<version> -t scopes-lambda-v2 .
#
# providers.json must list exactly `PROVIDERS` in src/resources.ts (test/image.test.ts checks it).
ARG PROVIDER_HOST_IMAGE=scope-provider-host:latest
ARG BUN_IMAGE=oven/bun:1.3.13-alpine

FROM ${PROVIDER_HOST_IMAGE}-builder AS providers
COPY providers.json /tmp/providers.json
RUN /opt/install-providers.sh /tmp/providers.json /opt/pulumi/plugins /opt/pulumi/schemas

# The package and its runtime dependencies (@nullplatform/plugin, the AWS SDK clients).
FROM ${BUN_IMAGE} AS package
WORKDIR /app/packages/lambda-v2
COPY package.json ./
RUN bun install --production
COPY src ./src
COPY entrypoint ./entrypoint

FROM ${PROVIDER_HOST_IMAGE}
COPY --from=providers --chown=65532:65532 /opt/pulumi /opt/pulumi
COPY --from=package /usr/local/bin/bun /usr/local/bin/bun
COPY --from=package --chown=65532:65532 /app/packages/lambda-v2 /app/packages/lambda-v2
