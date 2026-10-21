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
import { placeholderCode } from "./placeholder";

export const LOG_RETENTION_DAYS = 30;

export interface FunctionCode {
  imageUri?: string;
  s3Bucket?: string;
  s3Key?: string;
  code?: pulumi.asset.AssetArchive;
  runtime?: string;
  handler?: string;
  /** What the code belongs to: the deployment id, or `placeholder`. */
  description: string;
}

export interface DeployedFunction {
  fn: aws.lambda.Function;
  logGroup: aws.cloudwatch.LogGroup;
}

/** The code the function runs: the current release's asset, or the placeholder. */
export function codeOf(ctx: ScopeProgramContext, deploymentId: string | undefined, assetUrl: string | undefined): FunctionCode {
  const attributes = attributesOf(ctx);
  if (!deploymentId || !assetUrl) {
    const placeholder = placeholderCode(ctx);
    return placeholder.kind === "image"
      ? { imageUri: placeholder.imageUri, description: "placeholder" }
      : { code: placeholder.code, runtime: placeholder.runtime, handler: placeholder.handler, description: "placeholder" };
  }
  if (attributes.deployment_type === "docker-image") return { imageUri: assetUrl, description: deploymentId };
  const url = new URL(assetUrl);
  if (url.protocol !== "s3:") throw new Error(`zip asset ${assetUrl} is not an s3:// url`);
  return {
    s3Bucket: url.hostname,
    s3Key: url.pathname.replace(/^\//, ""),
    runtime: attributes.runtime,
    handler: attributes.handler,
    description: deploymentId,
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
      ...(code.code ? { code: code.code } : {}),
      ...(code.s3Bucket ? { s3Bucket: code.s3Bucket, s3Key: code.s3Key } : {}),
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
