/**
 * Pulumi's mock monitor: every resource the program declares is recorded here with its inputs,
 * and the program's outputs resolve to the mock's values. Runs under node (tsx): Pulumi's
 * runtime does not load under bun.
 */
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext, Release } from "@nullplatform/plugin/program";

export interface Recorded {
  type: string;
  name: string;
  inputs: Record<string, unknown>;
}

export const recorded: Recorded[] = [];

/** What the stack's previous run exported (`release_versions`); set per test. */
export const previousOutputs: { release_versions?: Record<string, string> } = {};

export async function installMocks(): Promise<void> {
  recorded.length = 0;
  await pulumi.runtime.setMocks(
    {
      newResource(args) {
        recorded.push({ type: args.type, name: args.name, inputs: args.inputs });
        const id = `${args.name}_id`;
        if (args.type === "pulumi:pulumi:StackReference") {
          return { id, state: { ...args.inputs, outputs: { ...previousOutputs }, secretOutputNames: [] } };
        }
        const arn = `arn:aws:mock:${args.type}:${args.name}`;
        return { id, state: { ...args.inputs, arn, version: "7", invokeArn: `${arn}:invoke`, dnsName: `${args.name}.elb.amazonaws.com` } };
      },
      call(args) {
        return args.inputs;
      },
    },
    "lambda-v2-tests",
    "test",
    true,
  );
}

export function contextFixture(overrides: {
  attributes?: Record<string, unknown>;
  releases?: Release[];
  providers?: Record<string, Record<string, unknown>>;
  scopeId?: string;
} = {}): ScopeProgramContext & { outputsRecorded: Record<string, unknown> } {
  const outputsRecorded: Record<string, unknown> = {};
  const scopeId = overrides.scopeId ?? "4242";
  return {
    scope: {
      id: scopeId,
      slug: "checkout",
      name: "Checkout",
      nrn: `organization=1:account=2:namespace=3:application=4:scope=${scopeId}`,
      dimensions: { environment: "prod" },
      attributes: {
        deployment_type: "docker-image",
        runtime: "nodejs22.x",
        handler: "index.handler",
        memory: 256,
        timeout: 30,
        ephemeral_storage: 512,
        architecture: "arm64",
        http_enabled: true,
        visibility: "public",
        reserved_concurrency: { type: "unreserved", value: 10 },
        provisioned_concurrency: { type: "unprovisioned", value: 5, warmup_alias: "" },
        vpc_enabled: false,
        dead_letter_target_arn: "",
        dead_letter_kms_key_arn: "",
        layers: [],
        continuous_delivery: { enabled: false, branches: ["main"] },
        ...overrides.attributes,
      },
      application: { id: "4", slug: "shop-api", repositoryUrl: "https://github.com/acme/shop-api" },
      namespace: { slug: "retail" },
      account: { slug: "acme" },
      parameters: [{ id: "p-1", name: "DATABASE_URL" }],
    },
    releases: overrides.releases ?? [],
    providers: {
      "cloud-providers": { account: { id: "123456789012", region: "us-east-1" }, networking: { hosted_public_zone_id: "Z1", hosted_zone_id: "Z2" } },
      vpc: { vpc: { id: "vpc-1", subnets: ["subnet-a"], security_groups: ["sg-a"] }, load_balancer: { public: { listener_arn: "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/pub/1/2" }, private: { listener_arn: "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/priv/1/2" } } },
      "scope-configurations": { deployment: { placeholder_image_uri: "123456789012.dkr.ecr.us-east-1.amazonaws.com/placeholder" } },
      ...overrides.providers,
    },
    naming: {
      resource: (suffix) => `np-${scopeId}-${suffix}`,
      dns: (label) => (label ? `${label}-${scopeId}` : scopeId),
    },
    secrets: { ref: (reference) => ({ $npSecret: reference }) },
    outputs: (values) => Object.assign(outputsRecorded, values),
    outputsRecorded,
  };
}

export const find = (type: string, name?: string) =>
  recorded.find((entry) => entry.type === type && (name === undefined || entry.name === name));
export const all = (type: string) => recorded.filter((entry) => entry.type === type);
/** Resolves an output, rejecting when the computation behind it threw. */
export const resolve = <T>(output: pulumi.Output<T> | T): Promise<T> =>
  (pulumi.output(output) as unknown as { promise(): Promise<T> }).promise();

/** Waits for a resource the program registers after its outputs resolved (dependsOn chains). */
export async function until(predicate: () => boolean, what: string, timeoutMs = 2000): Promise<void> {
  const started = Date.now();
  while (!predicate()) {
    if (Date.now() - started > timeoutMs) throw new Error(`${what} was never registered`);
    await new Promise((done) => setTimeout(done, 10));
  }
}

/** Pulumi wraps secret inputs; the mock sees the envelope, the provider sees the value. */
export const unwrapSecret = (value: unknown): unknown =>
  value && typeof value === "object" && "value" in (value as Record<string, unknown>) && "4dabf18193072939515e22adb298388d" in (value as Record<string, unknown>)
    ? (value as { value: unknown }).value
    : value;
