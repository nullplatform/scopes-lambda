import { strict as assert } from "node:assert";
import { before, describe, it } from "node:test";
import { all, contextFixture, find, installMocks, recorded, resolve, settle } from "./harness";

describe("the program: role, log group and function", () => {
  before(async () => {
    await installMocks();
  });

  it("declares the placeholder image function with the legacy role policies", async () => {
    recorded.length = 0;
    const { default: program } = await import("../src/program");
    const ctx = contextFixture();
    const outputs = await program(ctx);
    await resolve(outputs.function_arn);
    await settle();
    const fn = find("aws:lambda/function:Function");
    assert.ok(fn);
    assert.equal(fn.inputs.name, "4242-shop-api-checkout");
    assert.equal(fn.inputs.packageType, "Image");
    assert.equal(fn.inputs.imageUri, "123456789012.dkr.ecr.us-east-1.amazonaws.com/placeholder:latest");
    assert.equal(fn.inputs.description, "placeholder");
    assert.equal(fn.inputs.publish, true);
    assert.deepEqual(fn.inputs.architectures, ["arm64"]);
    assert.equal(fn.inputs.memorySize, 256);
    assert.equal(fn.inputs.reservedConcurrentExecutions, -1);
    assert.equal(fn.inputs.vpcConfig, undefined);
    const policies = all("aws:iam/rolePolicy:RolePolicy").map((entry) => entry.inputs.name).sort();
    assert.deepEqual(policies, ["cloudwatch-logs", "ecr-image-pull", "secrets-manager-parameters-read"]);
    assert.ok(find("aws:cloudwatch/logGroup:LogGroup"));
    assert.equal((find("aws:cloudwatch/logGroup:LogGroup") as unknown as { inputs: { retentionInDays: number } }).inputs.retentionInDays, 30);
    assert.equal(await resolve(outputs.function_name), "4242-shop-api-checkout");
    assert.equal(ctx.outputsRecorded.function_name, "4242-shop-api-checkout");
  });

  it("a zip scope with a release runs the release's s3 object with runtime and handler", async () => {
    recorded.length = 0;
    const { default: program } = await import("../src/program");
    const ctx = contextFixture({
      attributes: { deployment_type: "zip", runtime: "python3.12", handler: "app.handler", vpc_enabled: true, reserved_concurrency: { type: "reserved", value: 7 } },
      releases: [{ id: "r1", deploymentId: "d-1", weight: 100, role: "active", assets: [{ type: "lambda", url: "s3://builds/app/d-1.zip" }] }],
    });
    await resolve((await program(ctx)).function_arn);
    await settle();
    const fn = find("aws:lambda/function:Function");
    assert.ok(fn);
    assert.equal(fn.inputs.packageType, "Zip");
    assert.equal(fn.inputs.s3Bucket, "builds");
    assert.equal(fn.inputs.s3Key, "app/d-1.zip");
    assert.equal(fn.inputs.runtime, "python3.12");
    assert.equal(fn.inputs.handler, "app.handler");
    assert.equal(fn.inputs.description, "d-1");
    assert.equal(fn.inputs.reservedConcurrentExecutions, 7);
    assert.deepEqual(fn.inputs.vpcConfig, { subnetIds: ["subnet-a"], securityGroupIds: ["sg-a"] });
    assert.ok(find("aws:iam/rolePolicyAttachment:RolePolicyAttachment"));
  });

  it("a zip scope before any release runs the inline placeholder handler", async () => {
    recorded.length = 0;
    const { default: program } = await import("../src/program");
    await resolve((await program(contextFixture({ attributes: { deployment_type: "zip", runtime: "python3.12" } }))).function_arn);
    await settle();
    await settle();
    const fn = find("aws:lambda/function:Function");
    assert.ok(fn);
    assert.equal(fn.inputs.runtime, "nodejs22.x");
    assert.equal(fn.inputs.handler, "index.handler");
    assert.ok(fn.inputs.code);
  });

  it("a zip scope on a node runtime runs the placeholder on that very runtime", async () => {
    recorded.length = 0;
    const { default: program } = await import("../src/program");
    await resolve((await program(contextFixture({ attributes: { deployment_type: "zip", runtime: "nodejs20.x" } }))).function_arn);
    await settle();
    await settle();
    const fn = find("aws:lambda/function:Function");
    assert.ok(fn);
    assert.equal(fn.inputs.runtime, "nodejs20.x");
    assert.equal(fn.inputs.handler, "index.handler");
  });

  it("a dead-letter target adds the queue policy and the function config", async () => {
    recorded.length = 0;
    const { default: program } = await import("../src/program");
    await resolve((await program(contextFixture({
      attributes: { dead_letter_target_arn: "arn:aws:sqs:us-east-1:123456789012:dlq", dead_letter_kms_key_arn: "arn:aws:kms:us-east-1:123456789012:key/k" },
      providers: { "scope-configurations": { lambda: { role_policies: [{ name: "extra", policy: { Version: "2012-10-17", Statement: [] } }] } } },
    }))).function_arn);
    await settle();
    const fn = find("aws:lambda/function:Function");
    assert.deepEqual(fn?.inputs.deadLetterConfig, { targetArn: "arn:aws:sqs:us-east-1:123456789012:dlq" });
    const dlq = find("aws:iam/rolePolicy:RolePolicy", "np-lambda-4242-shop-api-checkout-role-np-lambda-dlq-4242");
    assert.ok(dlq);
    assert.match(String(dlq.inputs.policy), /sqs:SendMessage/);
    assert.match(String(dlq.inputs.policy), /kms:GenerateDataKey/);
    assert.ok(find("aws:iam/rolePolicy:RolePolicy", "np-lambda-4242-shop-api-checkout-role-extra"));
  });
});
