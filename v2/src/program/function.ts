/**
 * The function and its log group. The code is the current release's asset, or the placeholder
 * before any release; `publish: true` mints a version per code change, which the alias routes.
 */
import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, providersOf } from "./context";
import type { ExecutionRole } from "./iam";
import type { Names } from "./names";
import { placeholderCode, placeholderImage } from "./placeholder";

export const LOG_RETENTION_DAYS = 30;

export interface FunctionCode {
  imageUri?: pulumi.Input<string>;
  s3Bucket?: pulumi.Input<string | undefined>;
  s3Key?: pulumi.Input<string | undefined>;
  code?: pulumi.Input<pulumi.asset.AssetArchive | undefined>;
  runtime?: pulumi.Input<string>;
  handler?: pulumi.Input<string>;
  /** What the code belongs to: the deployment id, or `placeholder`. */
  description: pulumi.Input<string>;
}

export interface DeployedFunction {
  fn: aws.lambda.Function;
  logGroup: aws.cloudwatch.LogGroup;
}

/** Which deployment's asset the function runs; neither means the placeholder. */
export interface CodeSelection {
  deploymentId?: string;
  assetUrl?: string;
}

function s3Of(assetUrl: string): { bucket: string; key: string } {
  const url = new URL(assetUrl);
  if (url.protocol !== "s3:") throw new Error(`zip asset ${assetUrl} is not an s3:// url`);
  return { bucket: url.hostname, key: decodeURIComponent(url.pathname.replace(/^\//, "")) };
}

/**
 * The code the function runs, from a selection that may only be known once the previous run's
 * outputs are read: the selected deployment's asset, or the placeholder when there is none.
 */
export function codeOf(ctx: ScopeProgramContext, selection: pulumi.Output<CodeSelection>): FunctionCode {
  const attributes = attributesOf(ctx);
  const description = selection.apply((chosen) => chosen.deploymentId ?? "placeholder");
  if (attributes.deployment_type === "docker-image") {
    return { imageUri: selection.apply((chosen) => chosen.assetUrl ?? placeholderImage(ctx)), description };
  }
  const placeholder = placeholderCode(ctx);
  if (placeholder.kind !== "zip") throw new Error("a zip function's placeholder is inline code");
  const s3 = selection.apply((chosen) => (chosen.assetUrl ? s3Of(chosen.assetUrl) : undefined));
  return {
    s3Bucket: s3.apply((location) => location?.bucket),
    s3Key: s3.apply((location) => location?.key),
    code: selection.apply((chosen) => (chosen.assetUrl ? undefined : placeholder.code)),
    runtime: selection.apply((chosen) => (chosen.assetUrl ? attributes.runtime : placeholder.runtime)),
    handler: selection.apply((chosen) => (chosen.assetUrl ? attributes.handler : placeholder.handler)),
    description,
  };
}

export function lambdaFunction(
  ctx: ScopeProgramContext,
  names: Names,
  role: ExecutionRole,
  code: FunctionCode,
  environment: Record<string, pulumi.Input<string>>,
  opts: pulumi.ResourceOptions = {},
): DeployedFunction {
  const attributes = attributesOf(ctx);
  const { vpc } = providersOf(ctx);
  const logGroup = new aws.cloudwatch.LogGroup(names.logGroup, {
    name: names.logGroup,
    retentionInDays: LOG_RETENTION_DAYS,
    tags: { ManagedBy: "custom-scope-role", Module: "compute" },
  }, opts);
  const layers = [...attributes.layers];
  const fn = new aws.lambda.Function(
    names.functionName,
    {
      name: names.functionName,
      role: role.role.arn,
      publish: true,
      description: code.description,
      packageType: code.imageUri ? "Image" : "Zip",
      ...(code.imageUri ? { imageUri: code.imageUri } : {}),
      // Zip inputs resolve to undefined when they do not apply (an s3 asset or inline code).
      ...(code.code ? { code: code.code as pulumi.Input<pulumi.asset.AssetArchive> } : {}),
      ...(code.s3Bucket ? { s3Bucket: code.s3Bucket as pulumi.Input<string>, s3Key: code.s3Key as pulumi.Input<string> } : {}),
      ...(code.runtime ? { runtime: code.runtime, handler: code.handler } : {}),
      architectures: [attributes.architecture],
      memorySize: attributes.memory,
      timeout: attributes.timeout,
      ephemeralStorage: { size: attributes.ephemeral_storage },
      ...(layers.length ? { layers } : {}),
      ...(Object.keys(environment).length ? { environment: { variables: environment } } : {}),
      ...(attributes.vpc_enabled
        ? { vpcConfig: { subnetIds: vpc.vpc?.subnets ?? [], securityGroupIds: vpc.vpc?.security_groups ?? [] } }
        : {}),
      reservedConcurrentExecutions:
        attributes.reserved_concurrency.type === "reserved" ? (attributes.reserved_concurrency.value ?? -1) : -1,
      ...(attributes.dead_letter_target_arn ? { deadLetterConfig: { targetArn: attributes.dead_letter_target_arn } } : {}),
      tags: { ManagedBy: "custom-scope-role", Module: "compute" },
    },
    { ...opts, dependsOn: [logGroup, ...role.dependsOn] },
  );
  return { fn, logGroup };
}
