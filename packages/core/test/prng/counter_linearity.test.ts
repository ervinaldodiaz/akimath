import { describe, expect, it } from "vitest";

import { mix64, wordAt } from "../../src/prng/splitmix64.js";

/**
 * Addressing the stream by index gives the same words as walking it.
 *
 * This is the property that makes statelessness **structural**. With a cursor,
 * "the third draw" depends on how many draws happened before it, and a
 * generator that took one extra draw last year silently shifts every item after
 * it. With `wordAt(seed, n)` there is no cursor to get wrong: the *n*-th word is
 * a function of `(seed, n)` and nothing else, which is exactly what rederiving
 * an item years later requires.
 *
 * It holds because splitmix64 advances by a constant, so `n` steps of `x += Γ`
 * is `n × Γ`. That is an argument; this file is the check.
 */
const GAMMA = 0x9e37_79b9_7f4a_7c15n;
const MASK64 = 0xffff_ffff_ffff_ffffn;

/** The stateful walk, spelled the way the C spells it. */
function walk(seed: bigint, steps: number): bigint[] {
  let x = seed & MASK64;
  const out: bigint[] = [];
  for (let i = 0; i < steps; i += 1) {
    x = (x + GAMMA) & MASK64;
    out.push(mix64(x));
  }
  return out;
}

/** The extremes of the seed range, each named by the case it covers. */
const SEEDS: ReadonlyArray<{ name: string; seed: bigint }> = [
  { name: "zero", seed: 0n },
  { name: "one", seed: 1n },
  { name: "2^63", seed: 9223372036854775808n },
  {
    name: "2^64 − 1, where the counter wraps",
    seed: 18446744073709551615n,
  },
  { name: "-1", seed: -1n },
];

/**
 * Far enough out that the counter's *multiplication* wraps, not merely its
 * addition.
 *
 * `seed + (index + 1)·Γ` already exceeds 2^64 long before index 20 for a large
 * seed, so only a distant index reaches the case a missing mask would first
 * show.
 */
const INDEX_PAST_THE_MULTIPLICATION_WRAP = 1_000_000;

describe("the indexed word equals the walked word", () => {
  it("holds for twenty steps at every extreme of the seed range", () => {
    let compared = 0;
    for (const { name, seed } of SEEDS) {
      const walked = walk(seed, 20);
      for (const [index, word] of walked.entries()) {
        expect(wordAt(seed, index), `seed ${name} step ${index}`).toBe(word);
        compared += 1;
      }
    }
    expect(compared).toBe(SEEDS.length * 20);
    // eslint-disable-next-line no-console
    console.log(`  prng counter-linearity · ${compared} positions`);
  });

  it("holds where the counter itself wraps past 2^64", () => {
    const seed = 18446744073709551615n;
    const far = INDEX_PAST_THE_MULTIPLICATION_WRAP;
    expect(wordAt(seed, far)).toBe(
      mix64((seed + BigInt(far + 1) * GAMMA) & MASK64),
    );
  });

  it("a negative index is refused rather than silently reinterpreted", () => {
    expect(() => wordAt(0n, -1)).toThrow(RangeError);
    expect(() => wordAt(0n, 1.5)).toThrow(RangeError);
  });

  it("different indices give different words, which a function ignoring its index would not", () => {
    const words = new Set(Array.from({ length: 50 }, (_, i) => wordAt(7n, i)));
    expect(words.size).toBe(50);
  });
});
