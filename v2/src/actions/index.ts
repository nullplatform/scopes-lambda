/** Telemetry data actions: answered on the worker, next to the provider the program uses. */
import type { Context } from "../schema";

export async function readLogs(_ctx: Context): Promise<{ results: unknown[] }> {
  return { results: [] };
}

export async function listMetrics(_ctx: Context): Promise<{ results: unknown[] }> {
  return { results: [] };
}

export async function readMetric(_ctx: Context): Promise<{ results: unknown[] }> {
  return { results: [] };
}
