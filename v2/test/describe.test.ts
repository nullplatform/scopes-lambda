import { describe, expect, test } from "bun:test";
import { resolve } from "path";

async function describePackage() {
  const proc = Bun.spawn(["bun", "src/main.ts", "--describe"], {
    cwd: resolve(import.meta.dir, ".."),
    env: { ...process.env, NP_MODE: "test", NO_COLOR: "1", SUPPRESS_NO_CONFIG_WARNING: "1" },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text()]);
  expect(await proc.exited, stderr).toBe(0);
  return JSON.parse(stdout);
}

describe("--describe", () => {
  test("names an engine scope with the aws provider, every lifecycle action and the telemetry actions", async () => {
    const m = await describePackage();
    expect(m).toMatchObject({
      kind: "scope",
      name: "lambda-v2",
      displayName: "AWS Lambda v2",
      category: "Scope",
      provider: "AWS",
      subCategory: "Lambda",
      assetType: "docker-image",
      engine: { kind: "pulumi", providers: { aws: "7.2.0" }, credentialProfile: "platform" },
      program: { build: "build:program", entry: "./src/program.ts" },
    });
    expect(Object.keys(m.actions).sort()).toEqual([
      "create-scope", "delete-deployment", "delete-scope", "finalize-blue-green", "log:read", "metric:list",
      "metric:read", "refresh-scope", "rollback-deployment", "start-blue-green", "start-initial",
      "switch-traffic", "update-scope",
    ]);
    expect(m.actions["create-scope"].input.properties.orchestrator).toEqual({ type: "string", enum: ["engine"] });
    expect(m.actions["log:read"].lifecycle).toBe(false);
    expect(m.agent.sources).toEqual(["telemetry"]);
    expect(m.schema.properties.asset_type.default).toBe("docker-image");
    expect(m.schema.required).toContain("runtime");
  });
});
