import { describe, expect, it } from "vitest";

import { rederive, registryOf } from "../../src/registry.js";
import type { TemplateRef } from "../../src/template.js";
import { arithIntegerSubtractV1 } from "../../src/templates/arith-integer-subtract/v1.js";
import { arithIntegerSubtractV2 } from "../../src/templates/arith-integer-subtract/v2.js";

/**
 * A revision does not rewrite history.
 *
 * **The two versions differing is asserted, never assumed.** Without that, every
 * case here passes for two identical versions — and a versioning test that
 * cannot tell versions apart proves nothing at all.
 *
 * What separates them: v2 orders the terms below ladder step 3 and v1 does not,
 * so a seed drawing a smaller minuend produces different prompts. At step 3 and
 * above the two streams coincide, which is what makes the difference a real
 * behavioural change rather than a different PRNG walk.
 */
const registry = registryOf([arithIntegerSubtractV1, arithIntegerSubtractV2]);

const at = (version: number, seed: bigint, ladderStep: number): TemplateRef => ({
  templateId: "arith.integer.subtract",
  templateVersion: version,
  seed,
  ladderStep,
});

describe("a revision does not rewrite history", () => {
  it("the two versions genuinely differ at the same seed, so nothing here passes for one version twice", () => {
    let differed = 0;
    for (let seed = 0n; seed < 200n; seed += 1n) {
      const one = rederive(registry, at(1, seed, 2));
      const two = rederive(registry, at(2, seed, 2));
      if (one.prompt[0]?.kind === "text" && two.prompt[0]?.kind === "text") {
        if (one.prompt[0].value !== two.prompt[0].value) differed += 1;
      }
    }
    expect(differed, "v1 and v2 are indistinguishable").toBeGreaterThan(0);
  });

  it("v1 still produces exactly what it always produced — the shipped starter pack's `sub-2`", () => {
    const item = rederive(registry, at(1, 389n, 3));
    expect(item.left).toEqual({ num: 8, den: 1 });
    expect(item.right).toEqual({ num: 15, den: 1 });
    expect(item.answer).toEqual({ numerator: -7n, denominator: 1n });
  });

  it("above the ladder's negative threshold the two agree, because v2's change is scoped to steps below 3", () => {
    for (let seed = 0n; seed < 50n; seed += 1n) {
      expect(rederive(registry, at(1, seed, 3))).toEqual(
        rederive(registry, at(2, seed, 3)),
      );
    }
  });

  it("the ladder step is part of the key and not decoration, which is why the schema records it", () => {
    const three = rederive(registry, at(1, 389n, 3));
    const five = rederive(registry, at(1, 389n, 5));
    expect(three).not.toEqual(five);
  });
});
