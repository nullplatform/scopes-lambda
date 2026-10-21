import { describe, expect, test } from "bun:test";
import { readLogs } from "../../src/actions/logs";
import { contextOf, fakeClient } from "./support";

describe("log:read", () => {
  test("filters the function's log group for the asked window and answers sorted events with the next token", async () => {
    const logs = fakeClient([
      {
        events: [
          { timestamp: 1_700_000_002_000, message: "second" },
          { timestamp: 1_700_000_001_000, message: "first" },
        ],
        nextToken: "page-2",
      },
    ]);
    const ctx = contextOf({
      arguments: {
        start_time: "2023-11-14T22:13:00Z",
        end_time: "2023-11-14T22:14:00Z",
        limit: 50,
        filter_pattern: "ERROR",
        next_page_token: "page-1",
      },
    });
    const answer = await readLogs(ctx, { logs });
    expect(logs.inputs).toEqual([
      {
        logGroupName: "/aws/lambda/1-shop-main",
        startTime: Date.parse("2023-11-14T22:13:00Z"),
        endTime: Date.parse("2023-11-14T22:14:00Z"),
        limit: 50,
        filterPattern: "ERROR",
        nextToken: "page-1",
      },
    ]);
    expect(answer).toEqual({
      results: [
        { datetime: "2023-11-14T22:13:21.000Z", message: "first" },
        { datetime: "2023-11-14T22:13:22.000Z", message: "second" },
      ],
      next_page_token: "page-2",
    });
  });

  test("defaults to the last hour, 100 events and no filter", async () => {
    const logs = fakeClient([{ events: [] }]);
    const before = Date.now();
    const answer = await readLogs(contextOf({}), { logs });
    const [input] = logs.inputs;
    expect(input.limit).toBe(100);
    expect(input.filterPattern).toBeUndefined();
    expect(input.nextToken).toBeUndefined();
    expect(Number(input.endTime)).toBeGreaterThanOrEqual(before);
    expect(Number(input.endTime) - Number(input.startTime)).toBe(3_600_000);
    expect(answer).toEqual({ results: [], next_page_token: "" });
  });

  test("fails with a named error when the scope has no function yet", async () => {
    const logs = fakeClient([]);
    await expect(readLogs(contextOf({ params: {} }), { logs })).rejects.toMatchObject({
      code: "FUNCTION_NOT_CREATED",
    });
    expect(logs.inputs).toEqual([]);
  });
});
