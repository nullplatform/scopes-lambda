/**
 * The legacy names, exactly: a scope that moves from the bash implementation to this program
 * keeps its function, role and log group (the engine adopts them on refresh).
 */
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { providersOf } from "./context";

const AWS_NAME_LIMIT = 64;
const TARGET_GROUP_LIMIT = 32;
const DEFAULT_ROLE_PREFIX = "np-lambda-";

export interface Names {
  functionName: string;
  roleName: string;
  logGroup: string;
  alias: string;
  dlqPolicy: string;
  targetGroup: string;
  apiName: string;
  dnsName: string;
  secret(deploymentId: string): string;
}

const cut = (value: string, limit: number) => value.slice(0, limit);

export function names(ctx: ScopeProgramContext): Names {
  const { scope } = ctx;
  const functionName = cut(`${scope.id}-${scope.application.slug}-${scope.slug}`, AWS_NAME_LIMIT);
  const prefix = providersOf(ctx).configuration.lambda?.execution_role_prefix ?? DEFAULT_ROLE_PREFIX;
  const namespace = scope.namespace.slug;
  const application = scope.application.slug;
  return {
    functionName,
    roleName: cut(`${prefix}${functionName}-role`, AWS_NAME_LIMIT),
    logGroup: `/aws/lambda/${functionName}`,
    alias: "main",
    dlqPolicy: `np-lambda-dlq-${scope.id}`,
    targetGroup: cut(`${namespace.slice(0, 10)}-${application.slice(0, 10)}-${scope.slug.slice(0, 8)}`, TARGET_GROUP_LIMIT),
    apiName: `${namespace}-${application}-${scope.slug}`,
    // `<ns>-<app>-<scope>.<account>` under the zone, as the legacy Route53 setup names it.
    dnsName: `${namespace}-${application}-${scope.slug}.${scope.account.slug}`,
    secret: (deploymentId) => `nullplatform/${scope.id}/${deploymentId}/parameters`,
  };
}
