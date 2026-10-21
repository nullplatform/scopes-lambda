/**
 * What the function runs before its first deployment: the placeholder image the operator names
 * (ECR only, `:latest` when untagged), or an inline "hello" handler for zip functions.
 */
import * as pulumi from "@pulumi/pulumi";
import type { ScopeProgramContext } from "@nullplatform/plugin/program";
import { attributesOf, providersOf } from "./context";

export const DEFAULT_PLACEHOLDER_IMAGE =
  "235494813897.dkr.ecr.us-east-1.amazonaws.com/aws-lambda/nullplatform-lambda-placeholder:latest";
export const PLACEHOLDER_RUNTIME = "nodejs22.x";
export const PLACEHOLDER_HANDLER = "index.handler";

const PLACEHOLDER_SOURCE = `exports.handler = async () => ({
  statusCode: 200,
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ message: "nullplatform placeholder: deploy a release to replace it" }),
});
`;

export type PlaceholderCode =
  | { kind: "image"; imageUri: string }
  | { kind: "zip"; code: pulumi.asset.AssetArchive; runtime: string; handler: string };

export function placeholderImage(ctx: ScopeProgramContext): string {
  const configured = providersOf(ctx).configuration.deployment?.placeholder_image_uri ?? DEFAULT_PLACEHOLDER_IMAGE;
  if (configured.startsWith("public.ecr.aws")) {
    throw new Error(`placeholder image ${configured}: public ECR images cannot be used by Lambda; use a private ECR image`);
  }
  const name = configured.split("/").pop() ?? "";
  return name.includes(":") || configured.includes("@sha256:") ? configured : `${configured}:latest`;
}

export function placeholderCode(ctx: ScopeProgramContext): PlaceholderCode {
  const attributes = attributesOf(ctx);
  if (attributes.deployment_type === "zip") {
    return {
      kind: "zip",
      code: new pulumi.asset.AssetArchive({ "index.js": new pulumi.asset.StringAsset(PLACEHOLDER_SOURCE) }),
      // The handler is JavaScript: the scope's own runtime when it is a Node one, else a current one.
      runtime: attributes.runtime.startsWith("nodejs") ? attributes.runtime : PLACEHOLDER_RUNTIME,
      handler: PLACEHOLDER_HANDLER,
    };
  }
  return { kind: "image", imageUri: placeholderImage(ctx) };
}
