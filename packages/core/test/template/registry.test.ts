import { describe, expect, it } from "vitest";

import { issuable, rederive, registryOf, resolve } from "../../src/registry.js";
import type { Template, TemplateRef } from "../../src/template.js";
import { arithIntegerSubtractV1 } from "../../src/templates/arith-integer-subtract/v1.js";
import { arithIntegerSubtractV2 } from "../../src/templates/arith-integer-subtract/v2.js";

const ref = (over: Partial<TemplateRef> = {}): TemplateRef => ({
  templateId: "arith.integer.subtract",
  templateVersion: 1,
  seed: 389n,
  ladderStep: 3,
  ...over,
});

describe("a version resolves to the behaviour that version had", () => {
  const registry = registryOf([arithIntegerSubtractV1, arithIntegerSubtractV2]);

  it("resolves each version to its own generator", () => {
    expect(resolve(registry, ref({ templateVersion: 1 })).version).toBe(1);
    expect(resolve(registry, ref({ templateVersion: 2 })).version).toBe(2);
  });

  it("refuses a version it does not have, because falling back to the latest would rederive an old attempt as something it never was", () => {
    expect(() => resolve(registry, ref({ templateVersion: 99 }))).toThrow(
      /no template arith\.integer\.subtract@99/,
    );
    expect(() => resolve(registry, ref({ templateId: "nope" }))).toThrow(
      /no template nope@1/,
    );
  });

  it("refuses two templates claiming one key", () => {
    expect(() => registryOf([arithIntegerSubtractV1, arithIntegerSubtractV1])).toThrow(
      /two templates claim/,
    );
  });
});

describe("retirement stops issuing and never stops rederiving", () => {
  const retiredV1: Template = { ...arithIntegerSubtractV1, retired: true };
  const registry = registryOf([retiredV1, arithIntegerSubtractV2]);

  it("a retired version still rederives, because `attempts` is append-only and an item issued before the retirement must reconstruct", () => {
    const item = rederive(registry, ref({ templateVersion: 1 }));
    expect(item.left.num).toBe(8);
    expect(item.right.num).toBe(15);
  });

  it("and is never offered for issuing again", () => {
    expect(issuable(registry).map((t) => t.version)).toEqual([2]);
  });

  it("the control: nothing is retired by default, so an `issuable` that filtered everything would fail here", () => {
    const open = registryOf([arithIntegerSubtractV1, arithIntegerSubtractV2]);
    expect(issuable(open).map((t) => t.version)).toEqual([1, 2]);
  });
});
