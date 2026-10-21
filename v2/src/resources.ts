/**
 * The scope type: an engine scope. The orchestrator runs `src/program.ts` for every lifecycle
 * transition; this package answers the telemetry data actions on the worker.
 */
import { scope, Actions } from "@nullplatform/plugin/package";
import { listMetrics, readLogs, readMetric } from "./actions";
import { ASSET_TYPE, schema, uiSchema } from "./schema";

/** The stock AWS provider the program declares resources with; the worker image hosts it. */
export const PROVIDERS = { aws: "7.2.0" } as const;

export const lambda = scope({
  slug: "lambda-v2",
  name: "AWS Lambda v2",
  selectors: { category: "Scope", provider: "AWS", subCategory: "Lambda" },
  attributes: { schema },
  uiSchema,
  assetType: ASSET_TYPE,
  scopeType: { description: "Functions on AWS Lambda, declared by a program the platform runs" },
  telemetry: { logs: true },
  engine: "pulumi",
  providers: PROVIDERS,
  program: "./src/program.ts",
  credentialProfile: "platform",
  actions: {
    [Actions.LOG_READ]: readLogs,
    "metric:list": listMetrics,
    "metric:read": readMetric,
  },
});
