import { strict as assert } from "node:assert";
import { before, beforeEach, describe, it } from "node:test";
import type { Release } from "@nullplatform/plugin/program";
import { all, contextFixture, find, installMocks, previousOutputs, recorded, resolve, until, unwrapSecret } from "./harness";

const release = (deploymentId: string, weight: number, role: Release["role"]): Release => ({
  id: `rel-${deploymentId}`,
  deploymentId,
  weight,
  role,
  assets: [{ type: "docker-image", url: `123456789012.dkr.ecr.us-east-1.amazonaws.com/app:${deploymentId}` }],
});

async function run(releases: Release[], attributes: Record<string, unknown> = {}, providers: Record<string, Record<string, unknown>> = {}) {
  recorded.length = 0;
  const { default: program } = await import("../src/program");
  const ctx = contextFixture({ releases, attributes, providers });
  const outputs = await program(ctx);
  const versions = await resolve(outputs.release_versions as never);
  await resolve(outputs.alias_arn as never);
  const alias = find("aws:lambda/alias:Alias", "4242-shop-api-checkout-main");
  assert.ok(alias, "the main alias exists");
  return { ctx, versions: versions as Record<string, string>, alias: alias.inputs, fn: find("aws:lambda/function:Function")!.inputs };
}

describe("releases as alias routing", () => {
  before(async () => {
    await installMocks();
  });
  beforeEach(() => {
    delete previousOutputs.release_versions;
  });

  it("initial: the only release gets the alias, no routing, its version recorded", async () => {
    const { versions, alias, fn } = await run([release("d-1", 100, "candidate")]);
    assert.deepEqual(versions, { "d-1": "7" });
    assert.equal(alias.functionVersion, "7");
    assert.equal(alias.routingConfig, undefined);
    assert.equal(fn.imageUri, "123456789012.dkr.ecr.us-east-1.amazonaws.com/app:d-1");
    assert.equal(fn.description, "d-1");
  });

  it("blue-green at 0%: the alias stays on blue, the function runs green's code", async () => {
    previousOutputs.release_versions = { "d-1": "3" };
    const { versions, alias, fn } = await run([release("d-1", 100, "active"), release("d-2", 0, "candidate")]);
    assert.deepEqual(versions, { "d-1": "3", "d-2": "7" });
    assert.equal(alias.functionVersion, "3");
    assert.equal(alias.routingConfig, undefined);
    assert.equal(fn.description, "d-2");
  });

  it("switch to 30%: blue stays primary and green takes 0.3", async () => {
    previousOutputs.release_versions = { "d-1": "3", "d-2": "7" };
    const { alias } = await run([release("d-1", 70, "active"), release("d-2", 30, "candidate")]);
    assert.equal(alias.functionVersion, "3");
    assert.deepEqual(alias.routingConfig, { additionalVersionWeights: { "7": 0.3 } });
  });

  it("finalize: green alone, alias on green, blue forgotten", async () => {
    previousOutputs.release_versions = { "d-1": "3", "d-2": "7" };
    const { versions, alias } = await run([release("d-2", 100, "active")]);
    assert.deepEqual(versions, { "d-2": "7" });
    assert.equal(alias.functionVersion, "7");
    assert.equal(alias.routingConfig, undefined);
  });

  it("rollback: blue alone again, alias back on blue's recorded version", async () => {
    previousOutputs.release_versions = { "d-1": "3", "d-2": "7" };
    const { alias, fn } = await run([release("d-1", 100, "active")]);
    assert.equal(fn.description, "d-1");
    assert.equal(alias.functionVersion, "7", "blue is the current code again, so its version is the function's");
  });

  it("a release with no recorded version is a program error, not a guess", async () => {
    previousOutputs.release_versions = {};
    await assert.rejects(run([release("d-1", 100, "active"), release("d-2", 0, "candidate")]), /no published version on record/);
  });

  it("provisioned concurrency sits on the main alias; the warmup alias follows the newest release", async () => {
    previousOutputs.release_versions = { "d-1": "3" };
    const { alias } = await run(
      [release("d-1", 100, "active"), release("d-2", 0, "candidate")],
      { provisioned_concurrency: { type: "provisioned", value: 4, warmup_alias: "warm" } },
    );
    assert.equal(alias.functionVersion, "3");
    await until(() => Boolean(find("aws:lambda/provisionedConcurrencyConfig:ProvisionedConcurrencyConfig")), "provisioned concurrency");
    const provisioned = find("aws:lambda/provisionedConcurrencyConfig:ProvisionedConcurrencyConfig");
    assert.equal(provisioned?.inputs.provisionedConcurrentExecutions, 4);
    assert.equal(provisioned?.inputs.qualifier, "main");
    const warmup = find("aws:lambda/alias:Alias", "4242-shop-api-checkout-warm");
    assert.equal(warmup?.inputs.functionVersion, "7");
  });
});

describe("parameters", () => {
  before(async () => {
    await installMocks();
  });

  it("env strategy: each parameter is a secret reference in the environment", async () => {
    const { fn } = await run([release("d-1", 100, "active")]);
    assert.deepEqual(fn.environment, { variables: { DATABASE_URL: { $npSecret: "parameter:p-1" } } });
    assert.equal(all("aws:secretsmanager/secret:Secret").length, 0);
  });

  it("secretsmanager strategy: one secret per release, the function names the current one", async () => {
    previousOutputs.release_versions = { "d-1": "3" };
    const { fn } = await run(
      [release("d-1", 100, "active"), release("d-2", 0, "candidate")],
      {},
      { "scope-configurations": { deployment: { parameters_strategy: "secretsmanager" } } },
    );
    const secrets = all("aws:secretsmanager/secret:Secret").map((entry) => entry.inputs.name).sort();
    assert.deepEqual(secrets, ["nullplatform/4242/d-1/parameters", "nullplatform/4242/d-2/parameters"]);
    await until(() => all("aws:secretsmanager/secretVersion:SecretVersion").length === 2, "secret versions");
    const versions = all("aws:secretsmanager/secretVersion:SecretVersion");
    assert.deepEqual(unwrapSecret(versions[0].inputs.secretString), { $npSecret: "parameters:d-1" });
    assert.deepEqual(fn.environment, { variables: { NULLPLATFORM_PARAMETERS_SECRET: "nullplatform/4242/d-2/parameters" } });
  });
});
