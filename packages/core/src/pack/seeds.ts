/**
 * Which seed a generated item gets.
 *
 * **PURE**, and deliberately the dullest possible rule: the *n*th generated
 * item takes `base + n`.
 *
 * A clock- or random-derived seed would make a pack unreproducible, which
 * forecloses the byte-diff gate that keeps the committed artifact honest — and
 * `Math.random()` and `Date.now()` are banned in this package anyway.
 * `splitmix64` is counter-linear, so consecutive seeds still produce
 * well-distributed items: a counter costs nothing in item quality and buys
 * reproducibility outright.
 *
 * The base is declared rather than fixed at zero so a later pack can be a
 * different draw without a code change.
 */

/** The bounds of a Postgres signed `bigint`, which is what holds a seed. */
export const INT64_MAX = 9223372036854775807n;
export const INT64_MIN = -9223372036854775808n;

/**
 * The seed of the *n*th generated item: `base + n`.
 *
 * **There is no second bound on `base`.** It is checked through the same
 * arithmetic as every other index — an out-of-range base fails at index 0 — so
 * there is no separate check to keep in step with this one.
 */
export function seedAt(base: bigint, index: number): bigint {
  if (!Number.isInteger(index) || index < 0) {
    throw new RangeError(`seed index must be a non-negative integer, got ${index}`);
  }
  const seed = base + BigInt(index);
  if (seed > INT64_MAX || seed < INT64_MIN) {
    throw new RangeError(
      `seed ${seed} is outside the signed 64-bit range the column holds; ` +
        `a base of ${base} leaves room for fewer than ${index + 1} items`,
    );
  }
  return seed;
}
