/**
 * Exact rational arithmetic on `bigint`.
 *
 * **There is no `toString`, and that is the most important thing in this file.**
 *
 * The obvious method — render `numerator/denominator` — passes every arithmetic
 * test in the suite and is silently wrong, because this module reduces to lowest
 * terms and the frozen answer format does not. `packages/contract` already
 * decides what `5/4` means, its rule is golden-tested, and the Dart client
 * checks itself against the same fixture (risk R2). A reducing renderer here
 * would make `4/8` and `6/4` — both in the shipped starter pack — ungradeable,
 * and nothing in this package would notice.
 *
 * So `Rational` is a **method-free frozen interface**: there is no method to
 * reach for, `test/public_surface.test.ts` fails on any export whose name
 * matches `/render|format|canonical|toString/`, and rendering lives in the one
 * module that already owns canonicalisation.
 *
 * `bigint` and not a pair of numbers: past 2^53 a double stops counting, and an
 * exact answer that is quietly approximate is worse than no answer.
 */

/**
 * A rational in normal form: reduced to lowest terms, the sign on the
 * numerator, the denominator strictly positive, and zero written `0/1`.
 *
 * Normal form is what makes two equal values indistinguishable. Without it
 * `4/8` and `1/2` are different objects that compare unequal, and every lookup,
 * every set and every `toEqual` downstream is subtly wrong.
 */
export interface Rational {
  readonly numerator: bigint;
  readonly denominator: bigint;
}

function gcd(a: bigint, b: bigint): bigint {
  let x = a < 0n ? -a : a;
  let y = b < 0n ? -b : b;
  while (y !== 0n) {
    [x, y] = [y, x % y];
  }
  return x;
}

/**
 * A rational from a numerator and a denominator, normalised.
 *
 * Frozen at runtime, not merely `readonly` in the types: `readonly` is erased at
 * build, so a caller in plain JavaScript — or a caller that has cast the type
 * away — can reshape a value another module is still holding.
 *
 * **Zero needs no special case, and an earlier version of this function had
 * one.** It was guarded by a comment claiming the general path would give
 * `0/-1` for a negative denominator, and that was simply untrue: `gcd(0, d)` is
 * `|d|`, so the reduction yields `0/1` whatever the sign, and the branch was
 * dead code behind a false explanation. The mutation report found it — killing
 * the branch changed no behaviour — and `rationalOf(0n, -5n)` is pinned in the
 * suite, so the property stays checked without the code that pretended to
 * provide it.
 */
export function rationalOf(numerator: bigint, denominator = 1n): Rational {
  if (denominator === 0n) {
    throw new RangeError("a rational needs a non-zero denominator");
  }
  const sign = denominator < 0n ? -1n : 1n;
  const divisor = gcd(numerator, denominator);

  return Object.freeze({
    numerator: (sign * numerator) / divisor,
    denominator: (sign * denominator) / divisor,
  });
}

export function add(left: Rational, right: Rational): Rational {
  return rationalOf(
    left.numerator * right.denominator + right.numerator * left.denominator,
    left.denominator * right.denominator,
  );
}

export function subtract(left: Rational, right: Rational): Rational {
  return rationalOf(
    left.numerator * right.denominator - right.numerator * left.denominator,
    left.denominator * right.denominator,
  );
}

export function multiply(left: Rational, right: Rational): Rational {
  return rationalOf(
    left.numerator * right.numerator,
    left.denominator * right.denominator,
  );
}

/**
 * `left` divided by `right`.
 *
 * A zero divisor is named explicitly rather than left to fall through: without
 * that guard the denominator below becomes zero and `rationalOf` throws about a
 * *denominator*, which is true of the intermediate and says nothing about what
 * the caller did.
 */
export function divide(left: Rational, right: Rational): Rational {
  if (right.numerator === 0n) {
    throw new RangeError("cannot divide a rational by zero");
  }
  return rationalOf(
    left.numerator * right.denominator,
    left.denominator * right.numerator,
  );
}

/**
 * The reciprocal, which zero does not have.
 *
 * Zero is named explicitly for the same reason `divide` names it: the
 * fall-through error would blame a *denominator*, which is true of the
 * intermediate and says nothing about what the caller did.
 */
export function reciprocal(value: Rational): Rational {
  if (value.numerator === 0n) {
    throw new RangeError("zero has no reciprocal");
  }
  return rationalOf(value.denominator, value.numerator);
}

export function negate(value: Rational): Rational {
  return rationalOf(-value.numerator, value.denominator);
}

export function abs(value: Rational): Rational {
  return value.numerator < 0n ? negate(value) : value;
}

/** −1, 0 or 1. */
export function signOf(value: Rational): -1 | 0 | 1 {
  if (value.numerator === 0n) return 0;
  return value.numerator < 0n ? -1 : 1;
}

/**
 * Negative, zero or positive as `left` is less than, equal to or greater than
 * `right` — the comparator convention, so it drops into a sort.
 *
 * Cross-multiplied rather than divided: both denominators are positive by
 * normal form, so the comparison keeps its direction and stays exact.
 */
export function compare(left: Rational, right: Rational): number {
  const difference =
    left.numerator * right.denominator - right.numerator * left.denominator;
  if (difference === 0n) return 0;
  return difference < 0n ? -1 : 1;
}

/**
 * Whether two rationals are the same value.
 *
 * Normal form makes this a field comparison rather than a cross-multiplication.
 */
export function equals(left: Rational, right: Rational): boolean {
  return (
    left.numerator === right.numerator && left.denominator === right.denominator
  );
}

export function isInteger(value: Rational): boolean {
  return value.denominator === 1n;
}
