import { describe, expect, test } from "bun:test";
import legacy from "./legacy-schema.json";
import { legacySchema, outputs, schema, uiSchema } from "../src/schema";

describe("the schema", () => {
  test("is the legacy lambda schema, byte for byte", () => {
    expect(JSON.parse(JSON.stringify(legacySchema))).toEqual(legacy.schema);
    expect(JSON.parse(JSON.stringify(uiSchema))).toEqual(legacy.uiSchema);
  });

  test("adds read-only outputs only", () => {
    const added = Object.keys(schema.properties).filter((key) => !(key in legacySchema.properties));
    expect(added.sort()).toEqual(Object.keys(outputs).sort());
    for (const key of added) {
      expect((schema.properties as Record<string, { readOnly?: boolean; visibleOn?: string[] }>)[key]).toMatchObject({
        readOnly: true,
        visibleOn: ["read"],
      });
    }
    expect(schema.required).toEqual(legacySchema.required);
  });
});
