import { describe, expect, test } from "bun:test";
import { listMetrics, readMetric } from "../../src/actions/metrics";
import { contextOf, fakeClient } from "./support";

describe("metric:list", () => {
  test("answers the legacy catalogue", async () => {
    const answer = await listMetrics(contextOf({}));
    expect(answer.results.map((metric) => metric.name)).toEqual([
      "Invocations",
      "Duration",
      "Errors",
      "Throttles",
      "ConcurrentExecutions",
      "stream.iterator_age",
    ]);
    expect(answer.results[1]).toEqual({
      name: "Duration",
      title: "Duration",
      unit: "ms",
      available_filters: ["scope_id"],
      available_group_by: [],
    });
  });
});

describe("metric:read", () => {
  test("reads the metric's own statistic for the function over the window and answers one series", async () => {
    const cloudwatch = fakeClient([
      {
        Datapoints: [
          { Timestamp: new Date("2023-11-14T22:10:00Z"), Average: 20 },
          { Timestamp: new Date("2023-11-14T22:05:00Z"), Average: 10 },
        ],
      },
    ]);
    const answer = await readMetric(
      contextOf({
        arguments: {
          metric: "Duration",
          period: 60,
          start_time: "2023-11-14T22:00:00Z",
          end_time: "2023-11-14T22:15:00Z",
        },
      }),
      { cloudwatch },
    );
    expect(cloudwatch.inputs).toEqual([
      {
        Namespace: "AWS/Lambda",
        MetricName: "Duration",
        Dimensions: [{ Name: "FunctionName", Value: "1-shop-main" }],
        StartTime: new Date("2023-11-14T22:00:00Z"),
        EndTime: new Date("2023-11-14T22:15:00Z"),
        Period: 60,
        Statistics: ["Average"],
      },
    ]);
    expect(answer).toEqual({
      metric: "Duration",
      type: "gauge",
      period_in_seconds: 60,
      unit: "milliseconds",
      results: [
        {
          selector: { FunctionName: "1-shop-main" },
          data: [
            { timestamp: "2023-11-14T22:05:00.000Z", value: 10 },
            { timestamp: "2023-11-14T22:10:00.000Z", value: 20 },
          ],
        },
      ],
    });
  });

  test("maps stream.iterator_age to IteratorAge at its maximum, defaulting to Invocations over the last hour", async () => {
    const cloudwatch = fakeClient([{ Datapoints: [] }, { Datapoints: [] }]);
    await readMetric(contextOf({ arguments: { metric: "stream.iterator_age" } }), { cloudwatch });
    const defaulted = await readMetric(contextOf({}), { cloudwatch });
    expect(cloudwatch.inputs[0]).toMatchObject({ MetricName: "IteratorAge", Statistics: ["Maximum"], Period: 300 });
    expect(cloudwatch.inputs[1]).toMatchObject({ MetricName: "Invocations", Statistics: ["Sum"], Period: 300 });
    const { StartTime, EndTime } = cloudwatch.inputs[1] as { StartTime: Date; EndTime: Date };
    expect(EndTime.getTime() - StartTime.getTime()).toBe(3_600_000);
    expect(defaulted).toMatchObject({ metric: "Invocations", unit: "count", period_in_seconds: 300, results: [] });
  });

  test("a failed query is an empty series, never an error", async () => {
    const cloudwatch = fakeClient([new Error("AccessDenied")]);
    const answer = await readMetric(contextOf({ arguments: { metric: "Errors" } }), { cloudwatch });
    expect(answer.results).toEqual([]);
  });
});
