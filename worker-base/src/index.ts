import { createPlugin, registerManifest } from "@nullplatform/plugin";

// nullplatform worker-base — the minimal gRPC worker bridge.
//
// It registers with the control-plane agent and, on each action, re-exports
// NP_ACTION_CONTEXT and shells out to a bash entrypoint — the same contract as
// the classic in-process `exec` model, just spawned as a container the agent
// dials over gRPC/mTLS.
//
// NOTHING here is scope-specific. A package's worker image does:
//   FROM public.ecr.aws/nullplatform/worker-base
//   COPY . /app/pkg
//   ENV NP_SERVICE_PATH=/app/pkg/k8s  NP_SCOPE_ENTRYPOINT=/app/pkg/entrypoint
//   ENV NP_OVERRIDES_PATH=/app/pkg/azure        # optional, comma-separated
//   ENV NP_PACKAGE_NAME=scopes-k8s  NP_PACKAGE_VERSION=0.0.1
// so the service-path / overrides-path are BAKED into the image — the
// package-exec channel never needs a cmdline.
const NAME = process.env.NP_PACKAGE_NAME ?? "worker";
const VERSION = process.env.NP_PACKAGE_VERSION ?? "0.0.0";
const ENTRYPOINT = process.env.NP_SCOPE_ENTRYPOINT ?? "/app/entrypoint";
const SERVICE_PATH = process.env.NP_SERVICE_PATH ?? "/app";
const OVERRIDES_PATH = process.env.NP_OVERRIDES_PATH ?? "";
const COMMAND_TYPES = (process.env.NP_COMMAND_TYPES ?? "scope,service,action")
  .split(",").map((s) => s.trim()).filter(Boolean);
const SOURCES = (process.env.NP_AGENT_SOURCES ?? "service,telemetry")
  .split(",").map((s) => s.trim()).filter(Boolean);

const manifest = {
  name: NAME,
  version: VERSION,
  command_types: COMMAND_TYPES,
  agent: { selector: { package: NAME }, sources: SOURCES },
};
registerManifest(manifest);

// `np package publish` reads the manifest via --describe.
if (process.argv.includes("--describe")) {
  process.stdout.write(JSON.stringify(manifest));
  process.exit(0);
}

createPlugin({
  async execute(req) {
    // req.payload is the action context — what NP_ACTION_CONTEXT was in the
    // exec model. Re-export it and run the baked bash entrypoint unchanged.
    const ctx = req.payload.toString("utf-8");

    const args = ["bash", ENTRYPOINT, `--service-path=${SERVICE_PATH}`];
    for (const path of OVERRIDES_PATH.split(",").map((s) => s.trim()).filter(Boolean)) {
      args.push(`--overrides-path=${path}`);
    }

    const proc = Bun.spawn(args, {
      env: { ...process.env, NP_ACTION_CONTEXT: ctx },
      stdout: "pipe",
      stderr: "pipe",
    });

    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);

    // Mirror to the worker's own logs for `kubectl logs` / debugging.
    if (stdout) process.stdout.write(stdout);
    if (stderr) process.stderr.write(stderr);

    const ok = exitCode === 0;
    return {
      success: ok,
      data: { exitCode, stdout, stderr },
      ...(ok ? {} : { error: (stderr || stdout || `entrypoint exited ${exitCode}`).slice(-4000) }),
    };
  },
}).start();
