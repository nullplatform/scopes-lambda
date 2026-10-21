/**
 * Application parameters reach the function the way the operator chose:
 *  - `env`: each parameter is an environment variable whose value is a secret reference the
 *    worker resolves right before AWS sees it (the orchestrator never holds the value);
 *  - `secretsmanager`: one Secrets Manager secret per release (`nullplatform/<scope>/<deployment>/
 *    parameters`) holding every value as JSON, and the function gets the secret's name.
 */
import * as aws from "@pulumi/aws";
import type * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { providersOf } from "./context";
import type { Names } from "./names";

export type ParametersStrategy = "env" | "secretsmanager";

export const SECRET_ENV_NAME = "NULLPLATFORM_PARAMETERS_SECRET";

export function strategyOf(ctx: ScopeProgramContext): ParametersStrategy {
  return providersOf(ctx).configuration.deployment?.parameters_strategy === "secretsmanager" ? "secretsmanager" : "env";
}

/** A secret reference stands where a string value goes: the worker swaps it for the value. */
const asValue = (reference: { $npSecret: string }) => reference as unknown as string;

export interface Parameters {
  environment: Record<string, pulumi.Input<string>>;
  secrets: aws.secretsmanager.Secret[];
}

export function parameters(ctx: ScopeProgramContext, names: Names, opts: pulumi.ResourceOptions = {}): Parameters {
  if (strategyOf(ctx) === "env") {
    const environment: Record<string, pulumi.Input<string>> = {};
    for (const parameter of ctx.scope.parameters) {
      environment[parameter.name] = asValue(ctx.secrets.ref(`np://parameter/${parameter.id}`));
    }
    return { environment, secrets: [] };
  }
  const secrets = ctx.releases.map((release) => {
    const name = names.secret(release.deploymentId);
    const secret = new aws.secretsmanager.Secret(
      name,
      { name, tags: { "nullplatform:deployment-id": release.deploymentId, ManagedBy: "custom-scope-role" } },
      opts,
    );
    // The whole parameter set of the scope, as JSON; resolved by the worker per deployment.
    const version = new aws.secretsmanager.SecretVersion(
      `${name}-value`,
      { secretId: secret.id, secretString: asValue(ctx.secrets.ref(`np://parameters/${release.deploymentId}`)) },
      { ...opts, dependsOn: [secret] },
    );
    void version;
    return secret;
  });
  const current = ctx.releases.find((release) => release.role === "candidate") ?? ctx.releases.find((release) => release.role === "active");
  const environment: Record<string, pulumi.Input<string>> = current ? { [SECRET_ENV_NAME]: names.secret(current.deploymentId) } : {};
  return { environment, secrets };
}
