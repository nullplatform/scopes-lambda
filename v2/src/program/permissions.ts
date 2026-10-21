/**
 * Who may invoke the `main` alias: the operator's triggers (scope-configurations
 * `triggers.invoke_permissions`, filtered by scope as the legacy sync did) and, when the function
 * is exposed over HTTP, the load balancer or API Gateway.
 */
import * as aws from "@pulumi/aws";
import type * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { providersOf, type InvokePermission } from "./context";

const EXTERNAL_SID_PREFIX = "np-ext-";
const DEFAULT_ACTION = "lambda:InvokeFunction";

/** Entries meant for this scope: no `scope`, or the scope's slug or id. */
export function permissionsFor(ctx: ScopeProgramContext): InvokePermission[] {
  const entries = providersOf(ctx).configuration.triggers?.invoke_permissions ?? [];
  return entries.filter((entry) => !entry.scope || entry.scope === ctx.scope.slug || entry.scope === ctx.scope.id);
}

export function invokePermissions(
  ctx: ScopeProgramContext,
  fn: aws.lambda.Function,
  alias: aws.lambda.Alias,
  opts: pulumi.ResourceOptions = {},
): aws.lambda.Permission[] {
  return permissionsFor(ctx).map(
    (entry) =>
      new aws.lambda.Permission(
        `${EXTERNAL_SID_PREFIX}${entry.statement_id}`,
        {
          statementId: `${EXTERNAL_SID_PREFIX}${entry.statement_id}`,
          action: entry.action ?? DEFAULT_ACTION,
          function: fn.name,
          qualifier: alias.name,
          principal: entry.principal,
          ...(entry.source_arn ? { sourceArn: entry.source_arn } : {}),
          ...(entry.source_account ? { sourceAccount: entry.source_account } : {}),
        },
        opts,
      ),
  );
}
