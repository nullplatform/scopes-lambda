/**
 * The execution role, as the legacy tofu module declares it: logs, ECR pull, the parameters
 * secrets, the operator's extra policies, VPC access when enabled, an optional permissions
 * boundary, and the DLQ policy when a dead-letter target is set.
 */
import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, providersOf } from "./context";
import type { Names } from "./names";

const VPC_ACCESS_POLICY = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole";

export interface ExecutionRole {
  role: aws.iam.Role;
  /** Everything the function must wait for before it exists (policies attached). */
  dependsOn: pulumi.Resource[];
}

export function executionRole(
  ctx: ScopeProgramContext,
  names: Names,
  region: string,
  accountId: string,
  opts: pulumi.ResourceOptions = {},
): ExecutionRole {
  const attributes = attributesOf(ctx);
  const configuration = providersOf(ctx).configuration.lambda ?? {};
  const role = new aws.iam.Role(names.roleName, {
    name: names.roleName,
    assumeRolePolicy: JSON.stringify({
      Version: "2012-10-17",
      Statement: [{ Effect: "Allow", Principal: { Service: "lambda.amazonaws.com" }, Action: "sts:AssumeRole" }],
    }),
    ...(configuration.permissions_boundary ? { permissionsBoundary: configuration.permissions_boundary } : {}),
    tags: { ManagedBy: "custom-scope-role", Module: "iam" },
  }, opts);
  const logGroupArn = `arn:aws:logs:${region}:${accountId}:log-group:${names.logGroup}`;
  const inline: Record<string, unknown> = {
    "cloudwatch-logs": {
      Version: "2012-10-17",
      Statement: [
        { Effect: "Allow", Action: ["logs:CreateLogGroup"], Resource: logGroupArn },
        { Effect: "Allow", Action: ["logs:CreateLogStream", "logs:PutLogEvents"], Resource: `${logGroupArn}:*` },
      ],
    },
    "ecr-image-pull": {
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Action: ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"],
          Resource: `arn:aws:ecr:${region}:${accountId}:repository/*`,
        },
        { Effect: "Allow", Action: ["ecr:GetAuthorizationToken"], Resource: "*" },
      ],
    },
    "secrets-manager-parameters-read": {
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Action: ["secretsmanager:GetSecretValue"],
          Resource: `arn:aws:secretsmanager:*:*:secret:nullplatform/${ctx.scope.id}/*`,
        },
      ],
    },
  };
  for (const extra of configuration.role_policies ?? []) {
    inline[extra.name] = extra.policy;
  }
  if (attributes.dead_letter_target_arn) {
    const service = attributes.dead_letter_target_arn.split(":")[2];
    const statements: unknown[] = [
      {
        Effect: "Allow",
        Action: [service === "sns" ? "sns:Publish" : "sqs:SendMessage"],
        Resource: attributes.dead_letter_target_arn,
      },
    ];
    if (attributes.dead_letter_kms_key_arn) {
      statements.push({
        Effect: "Allow",
        Action: ["kms:GenerateDataKey", "kms:Decrypt"],
        Resource: attributes.dead_letter_kms_key_arn,
      });
    }
    inline[names.dlqPolicy] = { Version: "2012-10-17", Statement: statements };
  }
  const dependsOn: pulumi.Resource[] = Object.entries(inline).map(
    ([name, policy]) =>
      new aws.iam.RolePolicy(
        `${names.roleName}-${name}`,
        // A policy given as a document string is attached as is; an object is serialised once.
        { name, role: role.id, policy: typeof policy === "string" ? policy : JSON.stringify(policy) },
        opts,
      ),
  );
  if (attributes.vpc_enabled) {
    dependsOn.push(
      new aws.iam.RolePolicyAttachment(`${names.roleName}-vpc-access`, { role: role.name, policyArn: VPC_ACCESS_POLICY }, opts),
    );
  }
  return { role, dependsOn };
}
