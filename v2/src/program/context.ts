/**
 * Typed views over the program context: the attributes (the legacy schema's shape, defaults
 * applied by the orchestrator) and the provider categories the legacy workflows read.
 */
import type { ScopeProgramContext } from "@nullplatform/plugin/program";

export interface Concurrency {
  type: string;
  value?: number;
  warmup_alias?: string;
}

export interface LambdaAttributes {
  deployment_type: "docker-image" | "zip";
  runtime: string;
  handler: string;
  memory: number;
  timeout: number;
  ephemeral_storage: number;
  architecture: "arm64" | "x86_64";
  http_enabled: boolean;
  visibility: "public" | "private";
  reserved_concurrency: Concurrency;
  provisioned_concurrency: Concurrency;
  vpc_enabled: boolean;
  dead_letter_target_arn: string;
  dead_letter_kms_key_arn: string;
  layers: string[];
}

export interface CloudProviders {
  account?: { id?: string; region?: string };
  networking?: { hosted_public_zone_id?: string; hosted_zone_id?: string };
}

export interface VpcProvider {
  vpc?: { id?: string; subnets?: string[]; security_groups?: string[] };
  load_balancer?: { public?: { listener_arn?: string }; private?: { listener_arn?: string } };
}

export interface InvokePermission {
  statement_id: string;
  principal: string;
  source_arn?: string;
  source_account?: string;
  action?: string;
  scope?: string;
}

export interface ScopeConfigurations {
  deployment?: { placeholder_image_uri?: string; parameters_strategy?: "env" | "secretsmanager" };
  lambda?: {
    execution_role_prefix?: string;
    permissions_boundary?: string;
    role_policies?: { name: string; policy: unknown }[];
  };
  triggers?: { invoke_permissions?: InvokePermission[] };
  agent?: { null_agent_layer_arn?: string };
}

export interface Providers {
  cloud: CloudProviders;
  vpc: VpcProvider;
  configuration: ScopeConfigurations;
}

export function attributesOf(ctx: ScopeProgramContext): LambdaAttributes {
  return ctx.scope.attributes as unknown as LambdaAttributes;
}

export function providersOf(ctx: ScopeProgramContext): Providers {
  return {
    cloud: (ctx.providers["cloud-providers"] ?? {}) as CloudProviders,
    vpc: (ctx.providers.vpc ?? {}) as VpcProvider,
    configuration: (ctx.providers["scope-configurations"] ?? {}) as ScopeConfigurations,
  };
}

/** The candidate release when one exists (a deployment in flight), else the active one. */
export function currentRelease(ctx: ScopeProgramContext) {
  return ctx.releases.find((release) => release.role === "candidate") ?? ctx.releases.find((release) => release.role === "active");
}
