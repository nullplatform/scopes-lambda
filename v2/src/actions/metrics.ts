/** `metric:list` and `metric:read`: the legacy catalogue, read from CloudWatch's AWS/Lambda namespace. */
import { GetMetricStatisticsCommand } from "@aws-sdk/client-cloudwatch";
import type { Context } from "../schema";
import { cloudwatchClient, type AwsCommandClient } from "./aws";
import { argumentsOf, functionNameOf, positiveIntegerOf, stringOf, windowOf } from "./request";

const NAMESPACE = "AWS/Lambda";
const DEFAULT_METRIC = "Invocations";
const DEFAULT_PERIOD_SECONDS = 300;

type Statistic = "Sum" | "Average" | "Maximum";

interface MetricDefinition {
  title: string;
  /** The unit the catalogue shows. */
  unit: string;
  /** The unit a reading reports (the legacy spelt them differently). */
  readingUnit: string;
  statistic: Statistic;
  /** The CloudWatch metric behind the name. */
  cloudwatchName: string;
}

/** Every metric carries its own aggregation: a duration is averaged, a count summed, a level maxed. */
const CATALOGUE: Record<string, MetricDefinition> = {
  Invocations: { title: "Invocations", unit: "count", readingUnit: "count", statistic: "Sum", cloudwatchName: "Invocations" },
  Duration: { title: "Duration", unit: "ms", readingUnit: "milliseconds", statistic: "Average", cloudwatchName: "Duration" },
  Errors: { title: "Errors", unit: "count", readingUnit: "count", statistic: "Sum", cloudwatchName: "Errors" },
  Throttles: { title: "Throttles", unit: "count", readingUnit: "count", statistic: "Sum", cloudwatchName: "Throttles" },
  ConcurrentExecutions: {
    title: "Concurrent executions",
    unit: "count",
    readingUnit: "count",
    statistic: "Maximum",
    cloudwatchName: "ConcurrentExecutions",
  },
  "stream.iterator_age": {
    title: "Stream iterator age",
    unit: "ms",
    readingUnit: "milliseconds",
    statistic: "Maximum",
    cloudwatchName: "IteratorAge",
  },
};

const UNKNOWN_METRIC = (name: string): MetricDefinition => ({
  title: name,
  unit: "unknown",
  readingUnit: "unknown",
  statistic: "Sum",
  cloudwatchName: name,
});

export interface MetricListing {
  name: string;
  title: string;
  unit: string;
  available_filters: string[];
  available_group_by: string[];
}

export interface MetricSeries {
  selector: { FunctionName: string };
  data: Array<{ timestamp: string; value: number }>;
}

export interface MetricAnswer {
  metric: string;
  type: "gauge";
  period_in_seconds: number;
  unit: string;
  results: MetricSeries[];
}

export async function listMetrics(_ctx: Context): Promise<{ results: MetricListing[] }> {
  return {
    results: Object.entries(CATALOGUE).map(([name, definition]) => ({
      name,
      title: definition.title,
      unit: definition.unit,
      available_filters: ["scope_id"],
      available_group_by: [],
    })),
  };
}

interface Datapoint {
  Timestamp?: Date | string;
  Sum?: number;
  Average?: number;
  Maximum?: number;
}

function seriesOf(datapoints: Datapoint[], statistic: Statistic, functionName: string): MetricSeries[] {
  const data = datapoints
    .filter((point) => point.Timestamp !== undefined && typeof point[statistic] === "number")
    .map((point) => ({ timestamp: new Date(point.Timestamp as Date | string).toISOString(), value: point[statistic] as number }))
    .sort((left, right) => left.timestamp.localeCompare(right.timestamp));
  return data.length === 0 ? [] : [{ selector: { FunctionName: functionName }, data }];
}

export async function readMetric(ctx: Context, deps: { cloudwatch?: AwsCommandClient } = {}): Promise<MetricAnswer> {
  const functionName = functionNameOf(ctx);
  const args = argumentsOf(ctx);
  const metric = stringOf(args.metric) ?? DEFAULT_METRIC;
  const definition = CATALOGUE[metric] ?? UNKNOWN_METRIC(metric);
  const period = positiveIntegerOf(args.period, DEFAULT_PERIOD_SECONDS);
  const { start, end } = windowOf(args);
  const cloudwatch = deps.cloudwatch ?? (await cloudwatchClient(ctx));
  const answer: MetricAnswer = {
    metric,
    type: "gauge",
    period_in_seconds: period,
    unit: definition.readingUnit,
    results: [],
  };
  try {
    const response = await cloudwatch.send(
      new GetMetricStatisticsCommand({
        Namespace: NAMESPACE,
        MetricName: definition.cloudwatchName,
        Dimensions: [{ Name: "FunctionName", Value: functionName }],
        StartTime: new Date(start),
        EndTime: new Date(end),
        Period: period,
        Statistics: [definition.statistic],
      }),
    );
    const datapoints = Array.isArray(response.Datapoints) ? (response.Datapoints as Datapoint[]) : [];
    answer.results = seriesOf(datapoints, definition.statistic, functionName);
  } catch (error) {
    // A failed or empty query is an empty series, not an error: the graph shows no data instead
    // of the panel reporting a provider failure (as the legacy scope did).
    ctx.log?.fail?.(`metric ${metric} could not be read: ${error instanceof Error ? error.message : String(error)}`);
  }
  return answer;
}
