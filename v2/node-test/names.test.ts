import { strict as assert } from "node:assert";
import { describe, it } from "node:test";
import { names } from "../src/program/names";
import { placeholderImage } from "../src/program/placeholder";
import { contextFixture } from "./harness";

describe("names", () => {
  it("follow the legacy formats", () => {
    const n = names(contextFixture());
    assert.equal(n.functionName, "4242-shop-api-checkout");
    assert.equal(n.roleName, "np-lambda-4242-shop-api-checkout-role");
    assert.equal(n.logGroup, "/aws/lambda/4242-shop-api-checkout");
    assert.equal(n.dlqPolicy, "np-lambda-dlq-4242");
    assert.equal(n.targetGroup, "retail-shop-api-checkout");
    assert.equal(n.secret("d-9"), "nullplatform/4242/d-9/parameters");
  });

  it("cut a long function and role name at 64 characters, like the legacy scripts", () => {
    const ctx = contextFixture({ scopeId: "9".repeat(20) });
    ctx.scope.application.slug = "a".repeat(40);
    const n = names(ctx);
    assert.equal(n.functionName.length, 64);
    assert.equal(n.roleName.length, 64);
    assert.ok(n.roleName.startsWith("np-lambda-"));
  });

  it("honour the operator's role prefix", () => {
    const ctx = contextFixture({ providers: { "scope-configurations": { lambda: { execution_role_prefix: "acme-" } } } });
    assert.equal(names(ctx).roleName, "acme-4242-shop-api-checkout-role");
  });
});

describe("placeholder image", () => {
  it("appends :latest to an untagged image and refuses public ECR", () => {
    assert.equal(placeholderImage(contextFixture()), "123456789012.dkr.ecr.us-east-1.amazonaws.com/placeholder:latest");
    const tagged = contextFixture({ providers: { "scope-configurations": { deployment: { placeholder_image_uri: "x.dkr.ecr.us-east-1.amazonaws.com/p:v1" } } } });
    assert.equal(placeholderImage(tagged), "x.dkr.ecr.us-east-1.amazonaws.com/p:v1");
    const pub = contextFixture({ providers: { "scope-configurations": { deployment: { placeholder_image_uri: "public.ecr.aws/x/p" } } } });
    assert.throws(() => placeholderImage(pub), /public ECR/);
  });
});
