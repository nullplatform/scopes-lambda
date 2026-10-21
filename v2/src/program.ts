/**
 * The program: everything an AWS Lambda scope is, declared from the context the orchestrator
 * builds. Lifecycle is not here — the orchestrator passes the releases to serve and their
 * weights; the same declaration covers create, update, initial, blue-green, switch, finalize,
 * rollback and delete.
 */
import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext, ScopeProgram } from "@nullplatform/plugin/program";
import { currentRelease, providersOf } from "./program/context";
import { codeOf, lambdaFunction } from "./program/function";
import { executionRole } from "./program/iam";
import { names } from "./program/names";

const ASSET_TYPES = ["docker-image", "lambda"];

export function assetUrlOf(ctx: ScopeProgramContext): { deploymentId?: string; assetUrl?: string } {
  const release = currentRelease(ctx);
  if (!release) return {};
  const asset = release.assets.find((entry) => ASSET_TYPES.includes(entry.type)) ?? release.assets[0];
  return { deploymentId: release.deploymentId, assetUrl: asset?.url };
}

const program: ScopeProgram = async (ctx) => {
  const { cloud } = providersOf(ctx);
  const region = cloud.account?.region;
  const accountId = cloud.account?.id;
  if (!region || !accountId) throw new Error("the cloud-providers provider names no account.region / account.id");
  const provider = new aws.Provider("aws", {
    region,
    defaultTags: {
      tags: {
        "nullplatform:scope-id": ctx.scope.id,
        "nullplatform:namespace": ctx.scope.namespace.slug,
        "nullplatform:application": ctx.scope.application.slug,
        "nullplatform:scope": ctx.scope.slug,
        ManagedBy: "custom-scope-role",
      },
    },
  });
  // Every resource is a child of the scope component and inherits this provider: the worker's
  // credentials, this region.
  const root = new pulumi.ComponentResource("nullplatform:scope:Lambda", ctx.scope.slug, {}, { providers: [provider] });
  const opts: pulumi.ResourceOptions = { parent: root };
  const n = names(ctx);
  const role = executionRole(ctx, n, region, accountId, opts);
  const { deploymentId, assetUrl } = assetUrlOf(ctx);
  const code = codeOf(ctx, deploymentId, assetUrl);
  const { fn } = lambdaFunction(ctx, n, role, code, {}, opts);
  ctx.outputs({ function_name: n.functionName, function_arn: fn.arn, execution_role_arn: role.role.arn });
  return { function_name: n.functionName, function_arn: fn.arn, execution_role_arn: role.role.arn };
};

export default program;
