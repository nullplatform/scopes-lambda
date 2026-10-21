import { strict as assert } from "node:assert";
import { before, describe, it } from "node:test";
import { rulePriority } from "../src/program/http";
import { all, contextFixture, find, installMocks, recorded, resolve, settle } from "./harness";

async function run(attributes: Record<string, unknown> = {}, providers: Record<string, Record<string, unknown>> = {}) {
  recorded.length = 0;
  const { default: program } = await import("../src/program");
  const ctx = contextFixture({ attributes, providers });
  const outputs = await program(ctx);
  await resolve(outputs.alias_arn as never);
  const endpoint = await resolve(outputs.http_endpoint as never);
  const domain = await resolve(outputs.domain as never);
  await settle();
  return { ctx, endpoint, domain };
}

describe("http exposure and dns", () => {
  before(async () => {
    await installMocks();
  });

  it("public with a load balancer: target group, rule on the public listener, cname in the public zone", async () => {
    const { endpoint, domain } = await run();
    const tg = find("aws:lb/targetGroup:TargetGroup");
    assert.equal(tg?.inputs.name, "retail-shop-api-checkout");
    assert.equal(tg?.inputs.targetType, "lambda");
    const rule = find("aws:lb/listenerRule:ListenerRule");
    assert.equal(rule?.inputs.listenerArn, "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/pub/1/2");
    assert.equal(rule?.inputs.priority, rulePriority("4242"));
    assert.deepEqual(rule?.inputs.conditions, [{ hostHeader: { values: ["retail-shop-api-checkout-4242"] } }]);
    assert.ok(find("aws:lambda/permission:Permission", "AllowALBInvoke"));
    const record = find("aws:route53/record:Record");
    assert.equal(record?.inputs.zoneId, "Z1");
    assert.equal(record?.inputs.type, "CNAME");
    assert.equal(record?.inputs.name, "retail-shop-api-checkout-4242.acme.example");
    assert.deepEqual(record?.inputs.records, ["pub-123.us-east-1.elb.amazonaws.com"]);
    assert.equal(endpoint, "https://pub-123.us-east-1.elb.amazonaws.com");
    assert.equal(domain, "retail-shop-api-checkout-4242.acme.example");
    assert.equal(all("aws:apigatewayv2/api:Api").length, 0);
  });

  it("private: the private listener and the private zone", async () => {
    await run({ visibility: "private" });
    assert.equal(find("aws:lb/listenerRule:ListenerRule")?.inputs.listenerArn, "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/priv/1/2");
    assert.equal(find("aws:route53/record:Record")?.inputs.zoneId, "Z2");
  });

  it("no load balancer: an HTTP API with a $default route to the alias", async () => {
    const { endpoint } = await run({}, { vpc: {} });
    assert.equal(find("aws:apigatewayv2/api:Api")?.inputs.name, "retail-shop-api-checkout");
    const integration = find("aws:apigatewayv2/integration:Integration");
    assert.equal(integration?.inputs.integrationType, "AWS_PROXY");
    assert.equal(integration?.inputs.payloadFormatVersion, "2.0");
    assert.equal(find("aws:apigatewayv2/route:Route")?.inputs.routeKey, "$default");
    const stage = find("aws:apigatewayv2/stage:Stage");
    assert.equal(stage?.inputs.autoDeploy, true);
    assert.deepEqual(stage?.inputs.defaultRouteSettings, { throttlingBurstLimit: 5000, throttlingRateLimit: 10000 });
    assert.ok(find("aws:lambda/permission:Permission", "AllowAPIGatewayInvoke"));
    assert.match(endpoint, /execute-api/);
    assert.equal(all("aws:lb/targetGroup:TargetGroup").length, 0);
  });

  it("http disabled: nothing exposed, empty endpoint and domain", async () => {
    const { endpoint, domain } = await run({ http_enabled: false });
    assert.equal(all("aws:lb/targetGroup:TargetGroup").length, 0);
    assert.equal(all("aws:apigatewayv2/api:Api").length, 0);
    assert.equal(all("aws:route53/record:Record").length, 0);
    assert.equal(endpoint, "");
    assert.equal(domain, "");
  });

  it("operator triggers become np-ext permissions on the alias, filtered by scope", async () => {
    await run({}, {
      "scope-configurations": {
        triggers: {
          invoke_permissions: [
            { statement_id: "events", principal: "events.amazonaws.com", source_arn: "arn:aws:events:us-east-1:123456789012:rule/r" },
            { statement_id: "mine", principal: "sns.amazonaws.com", scope: "checkout" },
            { statement_id: "other", principal: "sns.amazonaws.com", scope: "another-scope" },
          ],
        },
      },
    });
    const sids = all("aws:lambda/permission:Permission").map((entry) => entry.inputs.statementId).sort();
    assert.deepEqual(sids, ["AllowALBInvoke", "np-ext-events", "np-ext-mine"]);
    assert.equal(find("aws:lambda/permission:Permission", "np-ext-events")?.inputs.qualifier, "main");
  });

  it("the rule priority is stable per scope and inside the listener's range", () => {
    assert.equal(rulePriority("4242"), rulePriority("4242"));
    assert.notEqual(rulePriority("4242"), rulePriority("4243"));
    assert.ok(rulePriority("1") >= 100 && rulePriority("1") < 50100);
  });
});
