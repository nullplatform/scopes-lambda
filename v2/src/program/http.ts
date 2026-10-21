/**
 * HTTP exposure, as the legacy modules declare it: behind the account's load balancer (a lambda
 * target group and a host-header listener rule on the public or private listener) when one
 * exists, else an HTTP API Gateway with a `$default` route to the alias.
 */
import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, providersOf } from "./context";
import type { Names } from "./names";

const HEALTH_CHECK = { path: "/health", interval: 35, timeout: 30 };
const API_THROTTLE = { throttlingBurstLimit: 5000, throttlingRateLimit: 10000 };
/** Listener-rule priorities must be unique per listener: one derived from the scope id, in a wide range. */
const PRIORITY_BASE = 100;
const PRIORITY_RANGE = 50000;

export function rulePriority(scopeId: string): number {
  let hash = 0;
  for (const char of scopeId) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return PRIORITY_BASE + (hash % PRIORITY_RANGE);
}

export type HttpExposure =
  | { kind: "none" }
  | { kind: "alb"; targetGroup: aws.lb.TargetGroup; rule: aws.lb.ListenerRule; dnsTarget: pulumi.Output<string>; endpoint: pulumi.Output<string> }
  | { kind: "api"; api: aws.apigatewayv2.Api; stage: aws.apigatewayv2.Stage; dnsTarget: pulumi.Output<string>; endpoint: pulumi.Output<string> };

export function httpExposure(
  ctx: ScopeProgramContext,
  names: Names,
  fn: aws.lambda.Function,
  alias: aws.lambda.Alias,
  opts: pulumi.ResourceOptions = {},
): HttpExposure {
  const attributes = attributesOf(ctx);
  if (!attributes.http_enabled) return { kind: "none" };
  const { vpc } = providersOf(ctx);
  const listenerArn =
    attributes.visibility === "private" ? vpc.load_balancer?.private?.listener_arn : vpc.load_balancer?.public?.listener_arn;
  const tags = { ManagedBy: "custom-scope-role", Module: "networking" };
  if (listenerArn) {
    const targetGroup = new aws.lb.TargetGroup(
      names.targetGroup,
      { name: names.targetGroup, targetType: "lambda", healthCheck: { enabled: true, ...HEALTH_CHECK }, tags },
      opts,
    );
    const permission = new aws.lambda.Permission(
      "AllowALBInvoke",
      {
        statementId: "AllowALBInvoke",
        action: "lambda:InvokeFunction",
        function: fn.name,
        qualifier: alias.name,
        principal: "elasticloadbalancing.amazonaws.com",
        sourceArn: targetGroup.arn,
      },
      opts,
    );
    new aws.lb.TargetGroupAttachment(
      `${names.targetGroup}-attachment`,
      { targetGroupArn: targetGroup.arn, targetId: alias.arn },
      { ...opts, dependsOn: [permission] },
    );
    const rule = new aws.lb.ListenerRule(
      `${names.targetGroup}-rule`,
      {
        listenerArn,
        priority: rulePriority(ctx.scope.id),
        actions: [{ type: "forward", targetGroupArn: targetGroup.arn }],
        conditions: [{ hostHeader: { values: [ctx.naming.dns(names.dnsName)] } }],
        tags,
      },
      opts,
    );
    const listener = aws.lb.getListenerOutput({ arn: listenerArn }, opts);
    const loadBalancer = listener.loadBalancerArn.apply((arn) => aws.lb.getLoadBalancer({ arn }, opts));
    const dnsTarget = loadBalancer.apply((lb) => lb.dnsName);
    return { kind: "alb", targetGroup, rule, dnsTarget, endpoint: dnsTarget.apply((dns) => `https://${dns}`) };
  }
  const api = new aws.apigatewayv2.Api(
    names.apiName,
    { name: names.apiName, protocolType: "HTTP", corsConfiguration: { allowOrigins: ["*"], allowMethods: ["*"], allowHeaders: ["*"] }, tags },
    opts,
  );
  const integration = new aws.apigatewayv2.Integration(
    `${names.apiName}-integration`,
    { apiId: api.id, integrationType: "AWS_PROXY", integrationUri: alias.invokeArn, payloadFormatVersion: "2.0" },
    opts,
  );
  new aws.apigatewayv2.Route(
    `${names.apiName}-default`,
    { apiId: api.id, routeKey: "$default", target: pulumi.interpolate`integrations/${integration.id}` },
    opts,
  );
  const stage = new aws.apigatewayv2.Stage(
    `${names.apiName}-main`,
    { apiId: api.id, name: "main", autoDeploy: true, defaultRouteSettings: API_THROTTLE, tags },
    opts,
  );
  new aws.lambda.Permission(
    "AllowAPIGatewayInvoke",
    {
      statementId: "AllowAPIGatewayInvoke",
      action: "lambda:InvokeFunction",
      function: fn.name,
      qualifier: alias.name,
      principal: "apigateway.amazonaws.com",
      sourceArn: pulumi.interpolate`${api.executionArn}/*/*`,
    },
    opts,
  );
  const dnsTarget = api.apiEndpoint.apply((endpoint) => endpoint.replace(/^https?:\/\//, ""));
  return { kind: "api", api, stage, dnsTarget, endpoint: stage.invokeUrl };
}
