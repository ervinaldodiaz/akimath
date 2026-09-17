import { describe, expect, it } from "vitest";

import {
  abs,
  add,
  compare,
  divide,
  equals,
  isInteger,
  multiply,
  negate,
  rationalOf,
  reciprocal,
  signOf,
  subtract,
  type Rational,
} from "../src/rational.js";

const r = (numerator: bigint, denominator: bigint = 1n): Rational =>
  rationalOf(numerator, denominator);

/** The pair, for asserting normal form directly. */
const pair = (value: Rational): [bigint, bigint] => [
  value.numerator,
  value.denominator,
];

/**
 * Every spelling of zero, including a negative denominator and a negative zero.
 *
 * Two zeroes that are not `equals` would be a defect nothing else in this file
 * could see. `rationalOf` once carried a dead branch and a false comment for
 * the negative-denominator case: BigInt has no negative zero (`-0n === 0n`),
 * and `gcd(0, d)` is `|d|`, so the general reduction already lands on `0/1`.
 * The branch is gone; the property is still checked.
 */
const ZEROES = [
  [0n, 1n],
  [0n, 5n],
  [0n, -5n],
  [-0n, 3n],
] as const;

/**
 * The guard's own words, because here the message *is* the assertion.
 *
 * Delete either guard and the operation still throws — from `rationalOf`, about
 * a denominator the caller never wrote — so matching on `/zero/` alone passes
 * for a guard that is gone. The mutation report caught exactly that.
 */
const DIVIDE_BY_ZERO = /divide a rational by zero/;

/** The reciprocal guard's own words, for the same reason. */
const NO_RECIPROCAL = /no reciprocal/;

/**
 * 2^53 + 1 — the first integer past the point where a double silently stops
 * counting, and the reason a rational is a pair of BigInts rather than a pair
 * of numbers.
 */
const BEYOND_DOUBLE_PRECISION = 9007199254740993n;

describe("a rational is always in normal form", () => {
  it("reduces to lowest terms", () => {
    expect(pair(r(4n, 8n))).toEqual([1n, 2n]);
    expect(pair(r(6n, 4n))).toEqual([3n, 2n]);
    expect(pair(r(100n, 10n))).toEqual([10n, 1n]);
  });

  it("keeps the sign on the numerator", () => {
    expect(pair(r(1n, -2n))).toEqual([-1n, 2n]);
    expect(pair(r(-1n, -2n))).toEqual([1n, 2n]);
    expect(pair(r(-3n, 6n))).toEqual([-1n, 2n]);
  });

  it("has exactly one representation of zero, at every sign of denominator", () => {
    for (const [n, d] of ZEROES) {
      expect(pair(r(n, d))).toEqual([0n, 1n]);
    }
  });

  it("refuses a zero denominator", () => {
    expect(() => r(1n, 0n)).toThrow(/denominator/);
    expect(() => r(0n, 0n)).toThrow(/denominator/);
  });

  it("two equal values are indistinguishable, which every comparison and lookup downstream relies on", () => {
    expect(pair(r(4n, 8n))).toEqual(pair(r(1n, 2n)));
    expect(equals(r(4n, 8n), r(1n, 2n))).toBe(true);
  });

  it("and unequal values are distinguishable — the control for an `equals` that always returns true, with numerator, denominator and sign varied independently", () => {
    expect(equals(r(1n, 2n), r(1n, 3n))).toBe(false);
    expect(equals(r(1n, 2n), r(3n, 2n))).toBe(false);
    expect(equals(r(1n, 2n), r(-1n, 2n))).toBe(false);
    expect(equals(r(0n), r(1n))).toBe(false);
  });

  it("is frozen, so a caller cannot reshape it", () => {
    const value = r(1n, 2n);
    expect(Object.isFrozen(value)).toBe(true);
    expect(() => {
      (value as { numerator: bigint }).numerator = 9n;
    }).toThrow(TypeError);
  });
});

describe("the arithmetic is exact", () => {
  it("adds without touching a float, including the starter pack's own fractions: a double makes 1/3 + 1/6 into 0.49999999999999994", () => {
    expect(pair(add(r(1n, 3n), r(1n, 6n)))).toEqual([1n, 2n]);
    expect(pair(add(r(3n, 4n), r(2n, 4n)))).toEqual([5n, 4n]);
    expect(pair(add(r(1n, 2n), r(1n, 3n)))).toEqual([5n, 6n]);
  });

  it("subtracts, including past zero", () => {
    expect(pair(subtract(r(5n, 8n), r(1n, 8n)))).toEqual([1n, 2n]);
    expect(pair(subtract(r(8n), r(15n)))).toEqual([-7n, 1n]);
    expect(pair(subtract(r(1n, 2n), r(1n, 2n)))).toEqual([0n, 1n]);
  });

  it("multiplies and divides", () => {
    expect(pair(multiply(r(2n), r(3n, 4n)))).toEqual([3n, 2n]);
    expect(pair(divide(r(3n, 4n), r(1n, 2n)))).toEqual([3n, 2n]);
    expect(pair(divide(r(-1n, 2n), r(2n)))).toEqual([-1n, 4n]);
  });

  it("refuses division by zero, blaming the division and not a denominator", () => {
    expect(() => divide(r(1n), r(0n))).toThrow(DIVIDE_BY_ZERO);
    expect(() => reciprocal(r(0n))).toThrow(NO_RECIPROCAL);
  });

  it("holds at magnitudes no double could", () => {
    const beyond = BEYOND_DOUBLE_PRECISION;
    expect(pair(add(r(beyond), r(1n)))).toEqual([9007199254740994n, 1n]);
    expect(pair(multiply(r(beyond), r(beyond)))).toEqual([beyond * beyond, 1n]);
  });

  it("does not grow denominators without reducing, which a naive add leaves as 12/36 and two equal values stop being equal", () => {
    expect(pair(add(r(1n, 6n), r(1n, 6n)))).toEqual([1n, 3n]);
  });
});

describe("comparison and inspection", () => {
  it("orders values, including across zero", () => {
    expect(compare(r(1n, 3n), r(1n, 2n))).toBeLessThan(0);
    expect(compare(r(1n, 2n), r(1n, 3n))).toBeGreaterThan(0);
    expect(compare(r(2n, 4n), r(1n, 2n))).toBe(0);
    expect(compare(r(-1n, 2n), r(1n, 3n))).toBeLessThan(0);
  });

  it("reports a sign, an absolute value and integrality", () => {
    expect(signOf(r(-3n, 4n))).toBe(-1);
    expect(signOf(r(0n))).toBe(0);
    expect(signOf(r(3n, 4n))).toBe(1);

    expect(pair(abs(r(-3n, 4n)))).toEqual([3n, 4n]);
    expect(pair(negate(r(3n, 4n)))).toEqual([-3n, 4n]);
    expect(pair(negate(r(0n)))).toEqual([0n, 1n]);

    expect(isInteger(r(4n, 2n))).toBe(true);
    expect(isInteger(r(3n, 2n))).toBe(false);
  });
});
