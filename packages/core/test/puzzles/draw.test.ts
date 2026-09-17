/**
 * `drawsFrom` is a cursor over one seed's stream, and both properties here are
 * asserted against the stream itself rather than against a range — a cursor
 * that reset its index on every call would return values in range for ever.
 *
 * A choice with one option must consume no index. Spending a word on it would
 * make the stream depend on the *shape* of the board rather than only on its
 * seed, so two boards differing in one cage size would diverge from that point
 * on. `grow` and Fisher–Yates both reach a bound of zero or below: an empty
 * neighbourhood and a one-element tail are ordinary, not errors.
 */

import { describe, expect, it } from "vitest";

import { intBetween } from "../../src/prng/splitmix64.js";
import { drawsFrom } from "../../src/puzzles/draw.js";

describe("a cursor over one seed's stream", () => {
  it("its draws are the stream's own words, at index 0, 1 and 2", () => {
    const draw = drawsFrom(99n);
    const wordAtIndexZero = intBetween(99n, 0, 0n, 5n);
    const wordAtTheNextIndex = intBetween(99n, wordAtIndexZero.nextIndex, 0n, 5n);

    expect(draw(5)).toBe(Number(wordAtIndexZero.value));
    expect(draw(5)).toBe(Number(wordAtTheNextIndex.value));
  });

  it("two cursors on one seed agree", () => {
    const a = drawsFrom(7n);
    const b = drawsFrom(7n);
    expect([a(9), a(9), a(9)]).toEqual([b(9), b(9), b(9)]);
  });

  it("different seeds do not", () => {
    const a = drawsFrom(7n);
    const b = drawsFrom(8n);
    expect([a(99), a(99), a(99)]).not.toEqual([b(99), b(99), b(99)]);
  });
});

describe("a choice with one option costs nothing", () => {
  it("a bound of zero draws zero", () => {
    expect(drawsFrom(1n)(0)).toBe(0);
  });

  it("a negative bound draws zero rather than throwing", () => {
    expect(drawsFrom(1n)(-1)).toBe(0);
  });

  it("it consumes no index", () => {
    const withZeros = drawsFrom(5n);
    withZeros(0);
    withZeros(0);
    const plain = drawsFrom(5n);

    expect([withZeros(9), withZeros(9)]).toEqual([plain(9), plain(9)]);
  });
});
