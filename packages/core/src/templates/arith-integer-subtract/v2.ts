import { intBetween } from "../../prng/splitmix64.js";
import { rationalOf } from "../../rational.js";
import type { GeneratedItem, Template, TemplateRef } from "../../template.js";

/**
 * `arith.integer.subtract` v2 — the same template, revised.
 *
 * **A separate file, and v1 is not touched.** This is the whole point of the
 * versioning: an attempt recorded against v1 must rederive as v1 forever, so a
 * revision cannot be an edit. The duplication between this file and its
 * predecessor is deliberate and permanent — a shared helper that both versions
 * called would be a single place where changing one changes both, which is
 * exactly what a version number exists to prevent.
 *
 * What changed: v1 could draw a subtrahend larger than the minuend, giving a
 * negative answer at every ladder step. v2 keeps the negative case for step 3
 * and above and orders the terms below it, so an early learner is not handed a
 * negative before the ladder has introduced one.
 */
function rangeFor(ladderStep: number): { readonly low: bigint; readonly high: bigint } {
  const high = BigInt(ladderStep) * 10n;
  return { low: 1n, high };
}

export function generateV2(ref: TemplateRef): GeneratedItem {
  const { low, high } = rangeFor(ref.ladderStep);

  const first = intBetween(ref.seed, 0, low, high);
  const second = intBetween(ref.seed, first.nextIndex, low, high);

  const negativesAllowed = ref.ladderStep >= 3;
  const a = first.value;
  const b = second.value;
  const left = negativesAllowed ? a : a >= b ? a : b;
  const right = negativesAllowed ? b : a >= b ? b : a;

  return {
    prompt: [
      { kind: "text", value: left.toString() },
      { kind: "operator", glyph: "−" },
      { kind: "text", value: right.toString() },
      { kind: "operator", glyph: "=" },
    ],
    answer: rationalOf(left - right),
    ladderStep: ref.ladderStep,
    operator: "-",
    left: { num: Number(left), den: 1 },
    right: { num: Number(right), den: 1 },
  };
}

export const arithIntegerSubtractV2: Template = Object.freeze({
  id: "arith.integer.subtract",
  version: 2,
  /**
   * Skill 1, the same one `content/pack.declaration.json` files its authored
   * items under. The declaration no longer says so for a template source: it
   * is read from here, so the two cannot disagree.
   */
  skillId: 1,
  generate: generateV2,
});
