import { describe, expect, it } from "vitest";

import {
  drawBelow,
  intBetween,
  rejectionLimit,
  wordAt,
} from "../../src/prng/splitmix64.js";

/**
 * A bounded draw is uniform, and its bound is reachable.
 *
 * `word % span` biases the low values whenever `span` does not divide 2^64:
 * with 2^64 = q·span + r, the first r residues get one extra chance each.
 *
 * **No golden vector can catch this.** A vector records whatever the draw
 * produced, biased or not, so removing the rejection changes the recorded
 * numbers and the replay test simply records the new ones. That is why
 * `rejectionLimit` is exported and asserted directly rather than left a local.
 */
const TWO_64 = 1n << 64n;

/**
 * The guard's own words, because here the message *is* the assertion.
 *
 * Delete the check and `rejectionLimit` divides by zero, so BigInt throws a
 * `RangeError` of its own — asserting only the *type* therefore passes for a
 * check that was deleted, which is precisely what the mutation report caught.
 * The empty-range guard below is the same shape one layer up: without it `span`
 * becomes zero and the `RangeError` arrives from two layers down, naming
 * nothing the caller did.
 */
const SPAN_MUST_BE_POSITIVE = /span must be positive/;

/** The empty-range guard's own words, for the reason above. */
const EMPTY_RANGE = /empty range/;

/**
 * The high end of a range whose span rejects very nearly half of all words.
 *
 * **A small span cannot exercise rejection at all.** The first version of the
 * tests below used a span of 3 and searched 100,000 draws for a rejected word;
 * 2^64 mod 3 is 1, so exactly one word in 2^64 is rejected and the search was
 * never going to find it. The rejection region is large only when the span is:
 * at 2^63 + 1 the limit is 2^63 + 1 itself, so very nearly half of all words
 * are rejected.
 */
const NEARLY_HALF_REJECTED_HIGH = 1n << 63n;

/**
 * The window the low half of a uniform draw must land in.
 *
 * Uniform is about 50%; the unrejected `word % span` form at this span maps two
 * different words onto every value below 2^63 − 1 and one onto the rest, so it
 * would come up low about 67% of the time. The band separates the two with room
 * for sampling noise.
 */
const UNIFORM_LOW_SHARE = { atLeast: 0.44, atMost: 0.56 };

/**
 * A word source that never yields an acceptable word.
 *
 * **Found by falsification, not by design.** Flipping one bit of `MASK64`
 * during the 2.6 matrix did not redden the suite — it hung the run, and the
 * whole thing had to be killed. A hang reports nothing: no failing test, no
 * message, just a job that eventually trips a timeout somebody has to go and
 * read. The sibling package's `vitest.config.ts` already records that a
 * synchronous infinite loop is not interruptible by the test runner at all.
 *
 * With the real kernel the convergence bound is unreachable by construction,
 * which is what makes it the kind of guard that rots unverified. `drawBelow`
 * takes its words as a value so a test can hand it a source that never yields.
 */
const alwaysRejected = (): bigint => (1n << 64n) - 1n;

describe("the rejection threshold is the one the range requires", () => {
  it("is 2^64 for a power of two, which divides it exactly so nothing is ever rejected", () => {
    for (const span of [1n, 2n, 256n, 1n << 32n]) {
      expect(rejectionLimit(span)).toBe(TWO_64);
    }
  });

  it("is the largest multiple of the span at or below 2^64", () => {
    for (const span of [3n, 5n, 6n, 7n, 10n, 100n, 12345n]) {
      const limit = rejectionLimit(span);
      expect(limit % span).toBe(0n);
      expect(limit).toBeLessThanOrEqual(TWO_64);
      expect(limit + span).toBeGreaterThan(TWO_64);
    }
  });

  it("refuses a span that cannot be drawn from, and says why", () => {
    expect(() => rejectionLimit(0n)).toThrow(SPAN_MUST_BE_POSITIVE);
    expect(() => rejectionLimit(-1n)).toThrow(SPAN_MUST_BE_POSITIVE);
  });
});

describe("a bounded draw stays in range and reaches both ends", () => {
  it("never leaves the range", () => {
    let drawn = 0;
    for (let index = 0; index < 500; index += 1) {
      const { value } = intBetween(42n, index, 1n, 6n);
      expect(value).toBeGreaterThanOrEqual(1n);
      expect(value).toBeLessThanOrEqual(6n);
      drawn += 1;
    }
    expect(drawn).toBe(500);
  });

  it("reaches both ends of the range — the control for a draw that returns a constant 3", () => {
    const seen = new Set<bigint>();
    for (let index = 0; index < 500; index += 1) {
      seen.add(intBetween(42n, index, 1n, 6n).value);
    }
    expect([...seen].sort((a, b) => Number(a - b))).toEqual([1n, 2n, 3n, 4n, 5n, 6n]);
  });

  it("a single-value range is the value, and consumes one index", () => {
    const { value, nextIndex } = intBetween(42n, 10, 7n, 7n);
    expect(value).toBe(7n);
    expect(nextIndex).toBe(11);
  });

  it("an empty range is refused, and says so rather than dividing by zero", () => {
    expect(() => intBetween(42n, 0, 5n, 4n)).toThrow(EMPTY_RANGE);
  });

  it("a rejected word consumes its index, so two callers from the same index cannot diverge", () => {
    const high = NEARLY_HALF_REJECTED_HIGH;
    const limit = rejectionLimit(high + 1n);
    expect(limit).toBe(high + 1n);

    let rejectedAt = -1;
    for (let index = 0; index < 1_000 && rejectedAt < 0; index += 1) {
      if (wordAt(1n, index) >= limit) rejectedAt = index;
    }
    expect(rejectedAt, "no rejection found to exercise").toBeGreaterThanOrEqual(0);

    const { nextIndex } = intBetween(1n, rejectedAt, 0n, high);
    expect(nextIndex).toBeGreaterThan(rejectedAt + 1);
  });

  it("rejection is what keeps a near-half span unbiased, measured rather than argued", () => {
    const high = NEARLY_HALF_REJECTED_HIGH;
    const draws = 2_000;
    let low = 0;
    let cursor = 0;
    for (let i = 0; i < draws; i += 1) {
      const drawn = intBetween(99n, cursor, 0n, high);
      cursor = drawn.nextIndex;
      if (drawn.value < high / 2n) low += 1;
    }
    expect(low / draws).toBeGreaterThan(UNIFORM_LOW_SHARE.atLeast);
    expect(low / draws).toBeLessThan(UNIFORM_LOW_SHARE.atMost);
  });

  it("the draw is reproducible from (seed, index) alone, whatever happened before it", () => {
    expect(intBetween(9n, 3, 1n, 1000n)).toEqual(intBetween(9n, 3, 1n, 1000n));
  });
});

describe("a broken kernel fails loudly instead of hanging", () => {
  it("gives up after a bounded number of rejections", () => {
    expect(() => drawBelow(1n, 0, alwaysRejected)).toThrow(/did not converge/);
  });

  it("rejects a word exactly equal to the exclusive limit, where q·span maps onto residue 0 and < differs from <=", () => {
    const words = (index: number): bigint => (index === 0 ? 10n : 3n);

    expect(drawBelow(10n, 0, words)).toEqual({ word: 3n, nextIndex: 2 });
  });

  it("consumes exactly the bound before giving up, which stops `< MAX` quietly becoming `<= MAX`", () => {
    let calls = 0;
    const never = (): bigint => {
      calls += 1;
      return (1n << 64n) - 1n;
    };

    expect(() => drawBelow(1n, 0, never)).toThrow(/did not converge/);
    expect(calls).toBe(100);
  });

  it("returns as soon as a word is below the limit — the control for a bound that fires for everything", () => {
    const thirdIsFine = (index: number): bigint => (index < 2 ? 999n : 5n);

    expect(drawBelow(10n, 0, thirdIsFine)).toEqual({ word: 5n, nextIndex: 3 });
  });
});
