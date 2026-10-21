import type { Context } from "../../src/schema";

/** A recording AWS client: every command's input is kept, the answers come from the table. */
export function fakeClient(answers: Array<Record<string, unknown> | Error>) {
  const inputs: Array<Record<string, unknown>> = [];
  return {
    inputs,
    async send(command: { input: object }) {
      inputs.push(command.input as Record<string, unknown>);
      const answer = answers.shift();
      if (answer instanceof Error) throw answer;
      return answer ?? {};
    },
  };
}

export function contextOf(overrides: {
  params?: Record<string, unknown>;
  arguments?: Record<string, unknown>;
  providers?: Record<string, Record<string, unknown>>;
}): Context {
  return {
    params: overrides.params ?? { function_name: "1-shop-main" },
    notification: { arguments: overrides.arguments ?? {} },
    settings: {
      providers: async () => overrides.providers ?? { "cloud-providers": { region: "us-east-1" } },
    },
  } as unknown as Context;
}
