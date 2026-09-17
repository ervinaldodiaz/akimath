import { describe, expect, it } from "vitest";

import { mix64, wordAt } from "../../src/prng/splitmix64.js";

/**
 * A second implementation, as an oracle.
 *
 * **What this buys, precisely:** the implementation reduces modulo 2^64 by
 * masking with a hexadecimal literal, and spells Vigna's three constants in
 * hex. This one reduces with `BigInt.asUintN`, which is a different mechanism,
 * and spells the same constants in **decimal**, which is a different
 * transcription. A slipped hex digit or a wrong mask has to be made twice, in
 * two notations, to survive.
 *
 * **What it does not buy:** it is not an independent authority on what
 * splitmix64 *is*. That is `reference.test.ts`, which compares against outputs
 * produced by compiling Vigna's own C. If both files were wrong in the same way
 * this one would agree with the implementation happily — so it is a
 * transcription check, and it is written down as one.
 */

/** 0x9e3779b97f4a7c15 */
const GAMMA = 11400714819323198485n;
/** 0xbf58476d1ce4e5b9 */
const M1 = 13787848793156543929n;
/** 0x94d049bb133111eb */
const M2 = 10723151780598845931n;

const u64 = (n: bigint): bigint => BigInt.asUintN(64, n);

/** Vigna's mixer, by a different route. */
function oracleMix(state: bigint): bigint {
  let z = u64(state);
  z = u64(u64(z ^ (z >> 30n)) * M1);
  z = u64(u64(z ^ (z >> 27n)) * M2);
  return u64(z ^ (z >> 31n));
}

/** The stateful form, exactly as the C walks it. */
function oracleStream(seed: bigint, count: number): bigint[] {
  let x = u64(seed);
  const out: bigint[] = [];
  for (let i = 0; i < count; i += 1) {
    x = u64(x + GAMMA);
    out.push(oracleMix(x));
  }
  return out;
}

/**
 * Seeds spanning the whole 64-bit range rather than sampling its middle, each
 * named by the case it covers.
 *
 * The negative ones are not hypothetical: a seed arrives from a signed Postgres
 * `bigint`, so `-1` and that column's minimum are real inputs.
 */
const SEEDS: ReadonlyArray<{ name: string; seed: bigint }> = [
  { name: "zero", seed: 0n },
  { name: "one", seed: 1n },
  { name: "two", seed: 2n },
  { name: "255", seed: 255n },
  {
    name: "2^32 − 1, where a 32-bit implementation would break",
    seed: 4294967295n,
  },
  { name: "2^32", seed: 4294967296n },
  {
    name: "2^63 − 1, the top of a signed Postgres bigint",
    seed: 9223372036854775807n,
  },
  { name: "2^63", seed: 9223372036854775808n },
  { name: "2^64 − 1", seed: 18446744073709551615n },
  { name: "-1, as a signed column spells it", seed: -1n },
  {
    name: "the bottom of a signed Postgres bigint",
    seed: -9223372036854775808n,
  },
  { name: "an arbitrary value", seed: 1477776061723855037n },
];

describe("two implementations, two notations, one stream", () => {
  it("agrees with the oracle across the whole seed range", () => {
    let compared = 0;
    for (const { name, seed } of SEEDS) {
      const expected = oracleStream(seed, 16);
      for (const [index, word] of expected.entries()) {
        expect(wordAt(seed, index), `seed ${name}, index ${index}`).toBe(word);
        compared += 1;
      }
    }
    expect(compared).toBe(SEEDS.length * 16);
    // eslint-disable-next-line no-console
    console.log(`  prng differential · ${compared} words over ${SEEDS.length} seeds`);
  });

  it("agrees on the mixer in isolation, including the extremes", () => {
    for (const state of [0n, 1n, 18446744073709551615n, 9223372036854775808n]) {
      expect(mix64(state)).toBe(oracleMix(state));
    }
  });

  it("the oracle disagrees when the implementation is wrong, which two functions both returning zero would not", () => {
    const wrong = (state: bigint): bigint => u64(state * M1);
    expect(wrong(12345n)).not.toBe(oracleMix(12345n));
  });
});
