/**
 * The AWS identity the data actions read with: the same lookups the worker's `platform`
 * credential profile makes for the provider, so logs and metrics are read by the role the
 * function was created with. Nothing here is stored; the agent's own identity assumes the role.
 */
import { CloudWatchClient } from "@aws-sdk/client-cloudwatch";
import { CloudWatchLogsClient } from "@aws-sdk/client-cloudwatch-logs";
import { fromTemporaryCredentials } from "@aws-sdk/credential-providers";
import type { AwsCredentialIdentityProvider } from "@smithy/types";
import type { Context } from "../schema";

/** The selector the Lambda scope's assume-role is registered under in `aws-iam-configuration`. */
const ROLE_SELECTOR = "lambda";
const SESSION_NAME = "nullplatform-lambda-v2-telemetry";

export interface AwsClientConfig {
  region: string | undefined;
  roleArn: string | undefined;
  credentials: AwsCredentialIdentityProvider | undefined;
}

/** What a handler needs of each client: `send`, so a test hands in a recording double. */
export interface AwsCommandClient {
  send(command: { input: object }): Promise<Record<string, unknown>>;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringAt(container: unknown, ...path: string[]): string | undefined {
  let current: unknown = container;
  for (const key of path) current = isObject(current) ? current[key] : undefined;
  return typeof current === "string" && current.length > 0 ? current : undefined;
}

export async function awsClientConfig(ctx: Context): Promise<AwsClientConfig> {
  const providers = await ctx.settings.providers(["cloud-providers", "aws-iam-configuration"]);
  const region = stringAt(providers["cloud-providers"], "region");
  const roleArn = stringAt(providers["aws-iam-configuration"], "arns", ROLE_SELECTOR);
  return {
    region,
    roleArn,
    credentials: roleArn
      ? fromTemporaryCredentials({ params: { RoleArn: roleArn, RoleSessionName: SESSION_NAME } })
      : undefined,
  };
}

async function clientOptions(ctx: Context) {
  const { region, credentials } = await awsClientConfig(ctx);
  return { ...(region ? { region } : {}), ...(credentials ? { credentials } : {}) };
}

export async function logsClient(ctx: Context): Promise<AwsCommandClient> {
  return new CloudWatchLogsClient(await clientOptions(ctx)) as unknown as AwsCommandClient;
}

export async function cloudwatchClient(ctx: Context): Promise<AwsCommandClient> {
  return new CloudWatchClient(await clientOptions(ctx)) as unknown as AwsCommandClient;
}
