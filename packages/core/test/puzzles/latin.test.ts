import { describe, expect, it } from "vitest";

import { latinSquare } from "../../src/puzzles/latin.js";

const rows = (square: readonly (readonly number[])[]): readonly (readonly number[])[] => square;

const columns = (square: readonly (readonly number[])[]): readonly number[][] =>
  square[0]!.map((_, col) => square.map((row) => row[col]!));

/**
 * Twelve squares off consecutive seeds, serialized.
 *
 * A cyclic square used unshuffled would satisfy every other assertion here and
 * make every KenKen in the pack the same puzzle wearing different cages, so
 * what is worth asserting is that the twelve are not all one square.
 */
const twelveSquaresAsJson = (size: number): readonly string[] =>
  Array.from({ length: 12 }, (_, i) => JSON.stringify(latinSquare(BigInt(i), size)));

/**
 * The square `latinSquare` would return if it never shuffled — symbol
 * `(row + col) % size`, the same diagonal in every one.
 *
 * Named explicitly, because "more than one square" would still pass for a
 * shuffle that only ever permuted symbols and left that structure standing.
 */
const cyclicSquare = (size: number): readonly (readonly number[])[] =>
  Array.from({ length: size }, (_, row) =>
    Array.from({ length: size }, (_, col) => ((row + col) % size) + 1),
  );

describe("a generated square is Latin", () => {
  it("every row and every column is a permutation, at every supported size", () => {
    for (let size = 3; size <= 6; size += 1) {
      const square = latinSquare(1234n, size);
      const wanted = new Set(Array.from({ length: size }, (_, i) => i + 1));

      expect(square, `size ${size}`).toHaveLength(size);
      for (const line of [...rows(square), ...columns(square)]) {
        expect(new Set(line), `size ${size}: ${line.join(",")}`).toEqual(wanted);
      }
    }
  });

  it("the same seed is the same square", () => {
    expect(latinSquare(77n, 5)).toEqual(latinSquare(77n, 5));
  });

  it("the square is not always the same one", () => {
    expect(new Set(twelveSquaresAsJson(4)).size).toBeGreaterThan(1);
  });

  it("it is not the cyclic square", () => {
    const cyclic = JSON.stringify(cyclicSquare(4));

    expect(twelveSquaresAsJson(4).some((square) => square !== cyclic)).toBe(true);
  });

  it("a size below three has no board to make", () => {
    expect(() => latinSquare(1n, 2)).toThrow(RangeError);
  });
});
