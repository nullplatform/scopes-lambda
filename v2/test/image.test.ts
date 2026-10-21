import { describe, expect, test } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";
import { PROVIDERS } from "../src/resources";

describe("the worker image", () => {
  test("installs exactly the providers the scope declares", () => {
    const manifest = JSON.parse(readFileSync(resolve(import.meta.dir, "../providers.json"), "utf8"));
    expect(manifest).toEqual(Object.entries(PROVIDERS).map(([name, version]) => ({ name, version })));
  });

  test("builds on the provider host image", () => {
    const dockerfile = readFileSync(resolve(import.meta.dir, "../Dockerfile"), "utf8");
    expect(dockerfile).toMatch(/FROM \$\{PROVIDER_HOST_IMAGE\}-builder AS providers/);
    expect(dockerfile).toMatch(/COPY providers.json/);
    expect(dockerfile).toMatch(/COPY --from=providers( --chown=\d+:\d+)? \/opt\/pulumi \/opt\/pulumi/);
  });

  test("ships the package at the agent's entrypoint for the data actions", () => {
    const dockerfile = readFileSync(resolve(import.meta.dir, "../Dockerfile"), "utf8");
    expect(dockerfile).toMatch(/\/app\/packages\/lambda-v2/);
    expect(dockerfile).toMatch(/COPY --from=package \/usr\/local\/bin\/bun/);
    const entrypoint = readFileSync(resolve(import.meta.dir, "../entrypoint"), "utf8");
    expect(entrypoint).toMatch(/exec bun \/app\/packages\/lambda-v2\/src\/main.ts/);
  });
});
