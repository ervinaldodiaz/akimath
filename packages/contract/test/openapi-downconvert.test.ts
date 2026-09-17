import { describe, expect, it } from "vitest";
import { z } from "zod";

import {
  CARRIED_THROUGH,
  REWRITTEN,
  toOpenApi303,
} from "../src/openapi/downconvert.js";

/**
 * The down-conversion, tested as a pure function over a JSON document.
 *
 * `ARCHITECTURE.md` §2 pins **OpenAPI 3.0.3** — Zod 4 emits JSON Schema, and
 * 3.0.3 is not JSON Schema. Every row below is a construct Zod actually
 * produces, checked against the installed version rather than assumed; several
 * of them were found by running it rather than by reading about it.
 */
const draft7 = (schema: z.ZodType): unknown =>
  z.toJSONSchema(schema, { target: "draft-7" });

/**
 * **The exclusive-bound rewrite is the one that needs saying.** draft-7 spells
 * it `exclusiveMinimum: 0`; 3.0.3 spells it `minimum: 0` plus
 * `exclusiveMinimum: true`, which is the draft-4 form it inherited.
 */
describe("what Zod emits becomes what 3.0.3 admits", () => {
  it("drops the dialect declaration", () => {
    const converted = toOpenApi303(draft7(z.object({ a: z.string() }))) as {
      $schema?: unknown;
    };
    expect(converted.$schema).toBeUndefined();
  });

  it("rewrites a nullable union as `nullable: true`", () => {
    const converted = toOpenApi303(draft7(z.object({ a: z.string().nullable() }))) as {
      properties: { a: Record<string, unknown> };
    };
    expect(converted.properties.a).toEqual({ type: "string", nullable: true });
  });

  it("collapses `const` to a single-valued enum", () => {
    const converted = toOpenApi303(draft7(z.object({ a: z.literal("x") }))) as {
      properties: { a: Record<string, unknown> };
    };
    expect(converted.properties.a).toEqual({ type: "string", enum: ["x"] });
  });

  it("rewrites a numeric exclusive bound as the boolean form", () => {
    const converted = toOpenApi303(draft7(z.object({ a: z.number().gt(0) }))) as {
      properties: { a: Record<string, unknown> };
    };
    expect(converted.properties.a).toEqual({
      type: "number",
      minimum: 0,
      exclusiveMinimum: true,
    });
  });

  it("strips the bounds Zod invents for an unbounded integer", () => {
    const converted = toOpenApi303(draft7(z.object({ a: z.int() }))) as {
      properties: { a: Record<string, unknown> };
    };
    expect(converted.properties.a).toEqual({ type: "integer" });
  });

  it("keeps bounds the author actually wrote, the control for stripping the synthetic pair", () => {
    const converted = toOpenApi303(draft7(z.object({ a: z.int().min(1).max(20) }))) as {
      properties: { a: Record<string, unknown> };
    };
    expect(converted.properties.a).toEqual({
      type: "integer",
      minimum: 1,
      maximum: 20,
    });
  });

  it("keeps a synthetic-looking minimum whose partner is a real bound", () => {
    const halfSynthetic = { type: "integer", minimum: Number.MIN_SAFE_INTEGER, maximum: 20 };
    expect(toOpenApi303(halfSynthetic)).toEqual(halfSynthetic);
  });

  it("keeps a synthetic-looking maximum whose partner is a real bound", () => {
    const halfSynthetic = { type: "integer", minimum: 1, maximum: Number.MAX_SAFE_INTEGER };
    expect(toOpenApi303(halfSynthetic)).toEqual(halfSynthetic);
  });

  it("drops `propertyNames`, which 3.0.3 does not have", () => {
    const converted = toOpenApi303(
      draft7(z.object({ a: z.record(z.string(), z.unknown()) })),
    ) as { properties: { a: Record<string, unknown> } };
    expect(converted.properties.a).toEqual({
      type: "object",
      additionalProperties: {},
    });
  });

  it("rewrites an array-valued type", () => {
    expect(
      toOpenApi303({ type: ["string", "null"] }),
    ).toEqual({ type: "string", nullable: true });
  });

  it("leaves what 3.0.3 already admits alone", () => {
    const untouched = {
      type: "object",
      properties: { a: { type: "string", format: "uuid" } },
      required: ["a"],
      additionalProperties: false,
    };
    expect(toOpenApi303(untouched)).toEqual(untouched);
  });
});

/**
 * **The most important behaviour in the file**, and the second case is its
 * control: a converter that refused *everything* would pass the refusal cases
 * and emit nothing, so the vocabulary the package's own schemas actually
 * produce is run through it too.
 */
describe("a construct it does not understand is refused, not passed through", () => {
  it("names the keyword and where it was", () => {
    expect(() =>
      toOpenApi303({ type: "object", properties: { a: { $dynamicRef: "#meta" } } }),
    ).toThrow(/\$dynamicRef.*properties\.a/s);
  });

  it("refuses the 2020-12 keywords by name", () => {
    for (const keyword of ["prefixItems", "$defs", "unevaluatedProperties", "dependentSchemas"]) {
      expect(() => toOpenApi303({ [keyword]: {} }), keyword).toThrow(
        new RegExp(keyword.replace("$", "\\$")),
      );
    }
  });

  it("and accepts every keyword the real schemas use", () => {
    const kitchenSink = z.object({
      id: z.uuid(),
      when: z.iso.datetime(),
      count: z.int().min(0),
      ratio: z.number(),
      name: z.string().min(1).max(64),
      flag: z.boolean(),
      kind: z.enum(["a", "b"]),
      list: z.array(z.string()),
      nested: z.object({ inner: z.string() }),
      opaque: z.record(z.string(), z.unknown()),
      maybe: z.string().nullable(),
      fixed: z.literal(7),
    });
    expect(() => toOpenApi303(draft7(kitchenSink))).not.toThrow();
  });
});

describe("the conversion is a pure function", () => {
  it("does not mutate what it is given", () => {
    const input = { type: ["string", "null"] as unknown };
    const before = JSON.stringify(input);
    toOpenApi303(input);
    expect(JSON.stringify(input)).toBe(before);
  });

  it("is idempotent on its own output, because the byte-diff gate emits twice", () => {
    const once = toOpenApi303(draft7(z.object({ a: z.string().nullable(), b: z.int() })));
    expect(toOpenApi303(once)).toEqual(once);
  });
});

/**
 * **Without these two cases the two sets are unverified.** Most of their
 * entries are keywords this package's own schemas never produce, so a wrong one
 * — a typo, or a keyword 3.0.3 does not actually admit — would sit there
 * indefinitely; mutation testing found exactly that, as a wall of surviving
 * string literals. The third case is what makes the two sets *closed* rather
 * than decorative.
 */
describe("the vocabulary is real, entry by entry", () => {
  /** A value each keyword can plausibly hold, so the entry is exercised. */
  const SAMPLE: Readonly<Record<string, unknown>> = {
    type: "string",
    properties: { a: { type: "string" } },
    required: ["a"],
    items: { type: "string" },
    enum: ["a"],
    format: "uuid",
    pattern: "^a$",
    minimum: 1,
    maximum: 2,
    minLength: 1,
    maxLength: 2,
    minItems: 1,
    maxItems: 2,
    uniqueItems: true,
    additionalProperties: false,
    description: "a",
    title: "a",
    default: "a",
    nullable: true,
    deprecated: true,
    readOnly: true,
    writeOnly: true,
    example: "a",
    $ref: "#/components/schemas/X",
  };

  it("every carried-through keyword is genuinely carried through", () => {
    expect(CARRIED_THROUGH.size).toBeGreaterThan(0);
    for (const keyword of CARRIED_THROUGH) {
      const sample = SAMPLE[keyword];
      expect(sample, `no sample for ${keyword}`).toBeDefined();
      expect(toOpenApi303({ [keyword]: sample }), keyword).toEqual({
        [keyword]: sample,
      });
    }
    // eslint-disable-next-line no-console
    console.log(`  downconvert · ${CARRIED_THROUGH.size} carried, ${REWRITTEN.size} rewritten`);
  });

  it("every rewritten keyword is genuinely rewritten", () => {
    const REWRITES: Readonly<Record<string, { input: unknown; output: unknown }>> = {
      $schema: { input: { $schema: "x", type: "string" }, output: { type: "string" } },
      const: { input: { const: 3 }, output: { enum: [3] } },
      anyOf: {
        input: { anyOf: [{ type: "string" }, { type: "null" }] },
        output: { type: "string", nullable: true },
      },
      exclusiveMinimum: {
        input: { type: "number", exclusiveMinimum: 1 },
        output: { type: "number", minimum: 1, exclusiveMinimum: true },
      },
      exclusiveMaximum: {
        input: { type: "number", exclusiveMaximum: 9 },
        output: { type: "number", maximum: 9, exclusiveMaximum: true },
      },
      propertyNames: {
        input: { type: "object", propertyNames: { type: "string" } },
        output: { type: "object" },
      },
    };

    expect(Object.keys(REWRITES).sort()).toEqual([...REWRITTEN].sort());
    for (const [keyword, { input, output }] of Object.entries(REWRITES)) {
      expect(toOpenApi303(input), keyword).toEqual(output);
    }
  });

  it("a keyword in neither set is refused", () => {
    expect(CARRIED_THROUGH.has("prefixItems")).toBe(false);
    expect(REWRITTEN.has("prefixItems")).toBe(false);
    expect(() => toOpenApi303({ prefixItems: [] })).toThrow(/prefixItems/);
  });
});
