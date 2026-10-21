/** `log:read`: the function's CloudWatch log group, filtered over the asked window. */
import { FilterLogEventsCommand } from "@aws-sdk/client-cloudwatch-logs";
import type { Context } from "../schema";
import { logsClient, type AwsCommandClient } from "./aws";
import { argumentsOf, functionNameOf, positiveIntegerOf, stringOf, windowOf } from "./request";

const DEFAULT_LIMIT = 100;

export interface LogEvent {
  datetime: string;
  message: string;
}

export interface LogsAnswer {
  results: LogEvent[];
  next_page_token: string;
}

interface FilteredEvent {
  timestamp?: number;
  message?: string;
}

export async function readLogs(ctx: Context, deps: { logs?: AwsCommandClient } = {}): Promise<LogsAnswer> {
  const functionName = functionNameOf(ctx);
  const args = argumentsOf(ctx);
  const { start, end } = windowOf(args);
  const logs = deps.logs ?? (await logsClient(ctx));
  const answer = await logs.send(
    new FilterLogEventsCommand({
      logGroupName: `/aws/lambda/${functionName}`,
      startTime: start,
      endTime: end,
      limit: positiveIntegerOf(args.limit, DEFAULT_LIMIT),
      filterPattern: stringOf(args.filter_pattern),
      nextToken: stringOf(args.next_page_token),
    }),
  );
  const events = Array.isArray(answer.events) ? (answer.events as FilteredEvent[]) : [];
  const results = events
    .filter((event) => typeof event.timestamp === "number")
    .map((event) => ({ datetime: new Date(event.timestamp as number).toISOString(), message: event.message ?? "" }))
    .sort((left, right) => left.datetime.localeCompare(right.datetime));
  return { results, next_page_token: stringOf(answer.nextToken) ?? "" };
}
