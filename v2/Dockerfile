# The lambda-v2 worker image: the scope provider host with the AWS provider the program declares
# (providers.json must list exactly `PROVIDERS` in src/resources.ts; test/image.test.ts checks it).
#
#   docker build --build-arg PROVIDER_HOST_IMAGE=scope-provider-host:<version> -t scopes-lambda-v2 .
#
# The telemetry data actions (src/actions) run through the agent's plugin runtime, not this image:
# this image only hosts the provider binaries and schemas behind the ExecutorPlugin service.
ARG PROVIDER_HOST_IMAGE=scope-provider-host:latest

FROM ${PROVIDER_HOST_IMAGE}-builder AS providers
COPY providers.json /tmp/providers.json
RUN /opt/install-providers.sh /tmp/providers.json /opt/pulumi/plugins /opt/pulumi/schemas

FROM ${PROVIDER_HOST_IMAGE}
COPY --from=providers --chown=65532:65532 /opt/pulumi /opt/pulumi
