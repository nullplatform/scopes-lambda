/**
 * Releases as alias routing. The function's code is the current release's asset and
 * `Function.version` is that release's version; every other release keeps the version the
 * previous run recorded as the stack output `release_versions` (read back through a reference to
 * this very stack). The `main` alias then points at the active release and routes the candidate's
 * share of traffic to its version — initial, blue-green, switch, finalize and rollback are all this.
 */
import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, currentRelease } from "./context";
import type { Names } from "./names";

export const RELEASE_VERSIONS_OUTPUT = "release_versions";
/** What code the function runs (deployment id and asset), recorded so a later run keeps it. */
export const CODE_SOURCE_OUTPUT = "code_source";

export interface CodeSource {
  deploymentId: string;
  assetUrl: string;
}

/** One reference to this very stack per program run: its previous outputs. */
const selfReferences = new WeakMap<ScopeProgramContext, pulumi.StackReference>();

function selfReference(ctx: ScopeProgramContext): pulumi.StackReference {
  let reference = selfReferences.get(ctx);
  if (!reference) {
    // The name a self-managed (DIY) backend requires: `organization/<project>/<stack>`.
    reference = new pulumi.StackReference(`organization/${pulumi.getProject()}/${pulumi.getStack()}`);
    selfReferences.set(ctx, reference);
  }
  return reference;
}

/** The code the previous run left on the function, or `undefined` on the first run. */
export function previousCodeSource(ctx: ScopeProgramContext): pulumi.Output<CodeSource | undefined> {
  return selfReference(ctx)
    .getOutput(CODE_SOURCE_OUTPUT)
    .apply((value) => (value && typeof value === "object" ? (value as CodeSource) : undefined));
}

export interface ReleaseVersions {
  /** deployment id → published version, for every release the scope serves. */
  versions: pulumi.Output<Record<string, string>>;
  /** Releases with no version on record: the program refuses to run with any. */
  missing: pulumi.Output<string[]>;
}

/** Awaits an output inside the program: a check that must fail the run before resources depend on it. */
export function settled<T>(output: pulumi.Output<T>): Promise<T> {
  return (output as unknown as { promise(): Promise<T> }).promise();
}

/** The previous run's `release_versions`, or `{}` on the first run. */
function previousVersions(ctx: ScopeProgramContext): pulumi.Output<Record<string, string>> {
  return selfReference(ctx)
    .getOutput(RELEASE_VERSIONS_OUTPUT)
    .apply((value) => (value ?? {}) as Record<string, string>);
}

/**
 * Each release's published version: the one whose asset the function runs now gets the function's
 * version, every other one the version recorded by a previous run.
 */
export function releaseVersions(
  ctx: ScopeProgramContext,
  fn: aws.lambda.Function,
  codeDeploymentId: pulumi.Output<string | undefined>,
): ReleaseVersions {
  const previous = previousVersions(ctx);
  // Never thrown from inside an output: a rejected output leaves unobserved promises behind.
  const resolved = pulumi.all([fn.version, previous, codeDeploymentId]).apply(([version, known, running]) => {
    const result: Record<string, string> = {};
    const missing: string[] = [];
    for (const release of ctx.releases) {
      if (release.deploymentId === running) result[release.deploymentId] = version;
      else if (known[release.deploymentId]) result[release.deploymentId] = known[release.deploymentId];
      else missing.push(`release ${release.id} (deployment ${release.deploymentId})`);
    }
    return { result, missing };
  });
  return { versions: resolved.apply((value) => value.result), missing: resolved.apply((value) => value.missing) };
}

export interface Routing {
  functionVersion: pulumi.Output<string>;
  additionalVersionWeights: pulumi.Output<Record<string, number> | undefined>;
}

/**
 * Where `main` points and what it routes, from the releases' roles and weights; with no release
 * at all, at the function's own published version (the placeholder's), never `$LATEST`, which a
 * provisioned concurrency config cannot attach to.
 */
export function routingOf(
  ctx: ScopeProgramContext,
  versions: pulumi.Output<Record<string, string>>,
  fallback: pulumi.Output<string>,
): Routing {
  const active = ctx.releases.find((release) => release.role === "active");
  const candidate = ctx.releases.find((release) => release.role === "candidate");
  const sole = ctx.releases.length === 1 ? ctx.releases[0] : undefined;
  const functionVersion = pulumi.all([versions, fallback]).apply(([map, own]) => {
    if (sole) return map[sole.deploymentId];
    if (candidate && active) return candidate.weight >= 100 ? map[candidate.deploymentId] : map[active.deploymentId];
    if (active) return map[active.deploymentId];
    if (candidate) return map[candidate.deploymentId];
    return own;
  });
  const additionalVersionWeights = versions.apply((map) => {
    if (!candidate || !active || sole || candidate.weight <= 0 || candidate.weight >= 100) return undefined;
    return { [map[candidate.deploymentId]]: candidate.weight / 100 };
  });
  return { functionVersion, additionalVersionWeights };
}

export interface Aliases {
  main: aws.lambda.Alias;
  warmup?: aws.lambda.Alias;
  provisioned?: aws.lambda.ProvisionedConcurrencyConfig;
}

export function aliases(
  ctx: ScopeProgramContext,
  names: Names,
  fn: aws.lambda.Function,
  versions: pulumi.Output<Record<string, string>>,
  opts: pulumi.ResourceOptions = {},
): Aliases {
  const attributes = attributesOf(ctx);
  const routing = routingOf(ctx, versions, fn.version);
  const main = new aws.lambda.Alias(
    `${names.functionName}-${names.alias}`,
    {
      name: names.alias,
      functionName: fn.name,
      functionVersion: routing.functionVersion,
      routingConfig: routing.additionalVersionWeights.apply((weights) =>
        weights ? { additionalVersionWeights: weights } : undefined,
      ),
    },
    opts,
  );
  const result: Aliases = { main };
  const warmupName = attributes.provisioned_concurrency.warmup_alias;
  const candidate = currentRelease(ctx);
  if (warmupName && candidate) {
    // The warmup alias always points at the newest release: pre-warmed before traffic reaches it.
    result.warmup = new aws.lambda.Alias(
      `${names.functionName}-${warmupName}`,
      { name: warmupName, functionName: fn.name, functionVersion: versions.apply((map) => map[candidate.deploymentId]) },
      opts,
    );
  }
  const provisioned = attributes.provisioned_concurrency;
  if (provisioned.type === "provisioned" && (provisioned.value ?? 0) > 0) {
    result.provisioned = new aws.lambda.ProvisionedConcurrencyConfig(
      `${names.functionName}-${names.alias}-provisioned`,
      { functionName: fn.name, qualifier: main.name, provisionedConcurrentExecutions: provisioned.value as number },
      { ...opts, dependsOn: [main] },
    );
  }
  return result;
}
