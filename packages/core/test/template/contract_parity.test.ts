import { describe, expect, it } from "vitest";

import {
  digestStoredAnswer,
  ItemSchema,
  parseStimulus,
  renderCanonicalAnswer,
} from "@akimath/contract";

import { rederive, registryOf } from "../../src/registry.js";
import type { GeneratedItem } from "../../src/template.js";
import { arithIntegerSubtractV1 } from "../../src/templates/arith-integer-subtract/v1.js";

/**
 * A generated item is acceptable to the frozen format.
 *
 * **This is the whole reason `@akimath/contract` is a devDependency.** Core is a
 * producer and the contract is the frozen acceptor; acceptance is a test-time
 * concern, so the reference is dev-only and core's `dependencies` key stays
 * absent (design D1). If the two ever disagree about what a well-formed item is,
 * this file goes red rather than a pack builder discovering it at F1.5.
 *
 * **`ItemSchema.safeParse` cannot see the payload**, which is why parity is not
 * asserted through it alone. Its `StimulusEnvelopeSchema` types `payload` as
 * `z.record(z.string(), z.unknown())`, so any object at all satisfies it — a
 * parity test built on `ItemSchema` would stay green for a stimulus core made up
 * entirely. `parseStimulus` is what actually runs the arithmetic payload schema,
 * and a case below proves it rejects what `ItemSchema` accepts.
 *
 * The answer travels the contract's own round trip — rendered by the contract,
 * then digested by the contract, which refuses anything not already
 * storage-canonical. A reducing renderer in core, the mistake `rational.ts`
 * exists to prevent, fails there.
 */
const PACK_SALT = "00112233445566778899aabbccddeeff";

/** Core's output in the shape the frozen `ItemSchema` expects. */
function asContractItem(item: GeneratedItem): unknown {
  const rendered = renderCanonicalAnswer(
    item.answer.numerator,
    item.answer.denominator === 1n ? undefined : item.answer.denominator,
  );
  const digest = digestStoredAnswer(PACK_SALT, rendered);
  if (!digest.ok) {
    throw new Error(`the contract refused core's own answer: ${digest.tag}`);
  }

  return {
    skill_id: 1,
    ladder_step: item.ladderStep,
    keypad: "item",
    stimulus: {
      kind: "arithmetic",
      payload: { operator: item.operator, left: item.left, right: item.right },
    },
    answer: { shape: "integer", digest: digest.digest },
    diagnosis: null,
  };
}

const generated = (seed: bigint, ladderStep = 3): GeneratedItem =>
  rederive(registryOf([arithIntegerSubtractV1]), {
    templateId: "arith.integer.subtract",
    templateVersion: 1,
    seed,
    ladderStep,
  });

describe("what core generates, the frozen format accepts", () => {
  it("passes the item schema", () => {
    for (let seed = 0n; seed < 25n; seed += 1n) {
      const parsed = ItemSchema.safeParse(asContractItem(generated(seed)));
      expect(parsed.success, `seed ${seed}: ${JSON.stringify(parsed.error?.issues)}`).toBe(true);
    }
  });

  it("passes the stimulus payload validator, which the item schema does not run", () => {
    for (let seed = 0n; seed < 25n; seed += 1n) {
      const item = asContractItem(generated(seed)) as { stimulus: unknown };
      expect(parseStimulus(item.stimulus), `seed ${seed}`).toBeNull();
    }
  });

  it("the control: `parseStimulus` rejects a payload `ItemSchema` happily accepts, so its `null` above means something", () => {
    const nonsense = { kind: "arithmetic", payload: { operator: "?", left: 1, right: 2 } };
    expect(parseStimulus(nonsense)).not.toBeNull();

    const stillAnItem = { ...(asContractItem(generated(0n)) as object), stimulus: nonsense };
    expect(ItemSchema.safeParse(stillAnItem).success).toBe(true);
  });

  it("core's exact answer survives the contract's own round trip, so a reducing renderer in core would fail here", () => {
    for (let seed = 0n; seed < 25n; seed += 1n) {
      const item = generated(seed);
      const rendered = renderCanonicalAnswer(item.answer.numerator);
      expect(digestStoredAnswer(PACK_SALT, rendered).ok, `seed ${seed}`).toBe(true);
    }
  });
});
