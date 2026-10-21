/** What a telemetry action is asked: the notification's arguments, and the function it concerns. */
import { ActionError } from "@nullplatform/plugin/package";
import type { Context } from "../schema";

const HOUR_MS = 3_600_000;

export function argumentsOf(ctx: Context): Record<string, unknown> {
  const raw = (ctx.notification as { arguments?: unknown } | undefined)?.arguments;
  return typeof raw === "object" && raw !== null && !Array.isArray(raw) ? (raw as Record<string, unknown>) : {};
}

/** The function the program recorded on the scope (`function_name` output); none before the first create. */
export function functionNameOf(ctx: Context): string {
  const name = (ctx.params as Record<string, unknown>).function_name;
  if (typeof name !== "string" || name.length === 0) {
    throw new ActionError("FUNCTION_NOT_CREATED", "the scope has no Lambda function yet: create it first");
  }
  return name;
}

/** An instant from an ISO string or epoch (seconds or milliseconds); `undefined` when absent or unreadable. */
export function instantOf(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value < 1e12 ? value * 1000 : value;
  if (typeof value === "string" && value.length > 0) {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return parsed;
    const numeric = Number(value);
    if (Number.isFinite(numeric)) return instantOf(numeric);
  }
  return undefined;
}

/** The asked window, or the last hour. */
export function windowOf(args: Record<string, unknown>, now = Date.now()): { start: number; end: number } {
  const end = instantOf(args.end_time) ?? now;
  const start = instantOf(args.start_time) ?? end - HOUR_MS;
  return { start, end };
}

export function positiveIntegerOf(value: unknown, fallback: number): number {
  const numeric = typeof value === "string" ? Number(value) : value;
  return typeof numeric === "number" && Number.isInteger(numeric) && numeric > 0 ? numeric : fallback;
}

export function stringOf(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
