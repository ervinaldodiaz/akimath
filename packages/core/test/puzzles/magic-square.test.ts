/**
 * The magic-square generator: the arithmetic it emits, the cells it prints and
 * the sizes it refuses.
 *
 * Six is refused up front rather than attempted. The format permits it and the
 * solver cannot verify it — 36 distinct values over 36 cells outrun
 * `SEARCH_NODE_BUDGET` every time — so attempting it would spend the whole
 * budget on boards the contract was always going to refuse.
 */

import { parsePuzzle } from "@akimath/contract";
import { describe, expect, it } from "vitest";

import {
  ATTEMPTS_PER_BOARD,
  generateMagicSquareBatch,
  type PuzzleCopy,
} from "../../src/puzzles/batch.js";
import {
  LARGEST_VERIFIABLE_SIZE,
  magicSquareCandidate,
} from "../../src/puzzles/magic-square.js";

const COPY: PuzzleCopy = {
  tutorialSteps: ['Cada fila y cada columna llegan al número de su ficha.'],
  referenceSheet: ['Ningún número se repite en todo el cuadro.'],
};

interface Payload {
  readonly board: {
    readonly size: number;
    readonly given: readonly { readonly row: number; readonly col: number }[];
    readonly solution: readonly (readonly number[])[];
    readonly blocked: readonly unknown[];
  };
  readonly row_targets: readonly number[];
  readonly column_targets: readonly number[];
}

const made = (seed: number, size = 3): Payload =>
  (magicSquareCandidate(BigInt(seed), size) as unknown as { payload: Payload }).payload;

const SEEDS = Array.from({ length: 25 }, (_, i) => i + 1);

/**
 * Every number from one to `highest`.
 *
 * Distinctness is the format's rule, and a permutation of these satisfies it
 * without anything having to search for it.
 */
const everyNumberUpTo = (highest: number): number[] =>
  Array.from({ length: highest }, (_, i) => i + 1);

/**
 * How many cells a board comes with printed.
 *
 * The thresholds these are held to were **measured, not chosen**. Below 0.6 a
 * 4×4 fails as `search_budget_exhausted` far more often than it fails as
 * `solution_not_unique` — the boards are not worse, they are unverifiable. A
 * 3×3 needs none of that and would be given away by the same fraction: at 0.6
 * it prints five of nine cells, which is most of the answer.
 */
const printedCells = (size: number): number => made(1, size).board.given.length;

describe("the arithmetic is true by construction", () => {
  it("every cell holds a different number from 1 to size squared", () => {
    for (const size of [3, 4, 5]) {
      for (const seed of SEEDS) {
        const payload = made(seed, size);
        const flat = payload.board.solution.flat();
        const wanted = everyNumberUpTo(size * size);

        expect([...flat].sort((a, b) => a - b), `${size} seed ${seed}`).toEqual(wanted);
      }
    }
  }, 60_000);

  it("each target is what its line actually adds up to", () => {
    for (const seed of SEEDS) {
      const payload = made(seed, 4);
      const solution = payload.board.solution;

      for (const [row, values] of solution.entries()) {
        expect(payload.row_targets[row]).toBe(values.reduce((a, b) => a + b, 0));
      }
      for (let col = 0; col < 4; col += 1) {
        expect(payload.column_targets[col]).toBe(
          solution.reduce((total, values) => total + values[col]!, 0),
        );
      }
    }
  });

  it("there are as many targets as lines", () => {
    for (const size of [3, 4, 5]) {
      const payload = made(1, size);
      expect(payload.row_targets).toHaveLength(size);
      expect(payload.column_targets).toHaveLength(size);
    }
  });

  it("nothing is blocked — a magic square has no holes", () => {
    expect(made(1).board.blocked).toEqual([]);
  });
});

describe("what it prints", () => {
  it("the printed cells are distinct and inside the board", () => {
    for (const size of [3, 4, 5]) {
      for (const seed of SEEDS) {
        const given = made(seed, size).board.given;
        const keys = given.map((c) => `${c.row},${c.col}`);

        expect(new Set(keys).size, `${size} seed ${seed}`).toBe(given.length);
        for (const cell of given) {
          expect(cell.row).toBeLessThan(size);
          expect(cell.col).toBeLessThan(size);
        }
      }
    }
  }, 60_000);

  it("it never prints the whole board, which would be a picture", () => {
    for (const size of [3, 4, 5]) {
      const payload = made(1, size);
      expect(payload.board.given.length).toBeLessThan(size * size);
      expect(payload.board.given.length).toBeGreaterThan(0);
    }
  });

  it("a small square prints little, a larger one prints more", () => {
    expect(printedCells(3)).toBeLessThanOrEqual(3);
    expect(printedCells(4)).toBeGreaterThan(16 / 3);
    expect(printedCells(5)).toBeGreaterThan(25 / 3);
  });

  it("the printed cells come in a stable order", () => {
    for (const seed of SEEDS) {
      const given = made(seed, 4).board.given;
      expect(given).toEqual(
        [...given].sort((a, b) => a.row - b.row || a.col - b.col),
      );
    }
  });
});

describe("a size the validator cannot decide is refused up front", () => {
  it("six is named, not attempted", () => {
    expect(magicSquareCandidate(1n, 6)).toBe('size_not_verifiable');
  });

  it("and so is a board too small to be one", () => {
    expect(magicSquareCandidate(1n, 2)).toBe('size_below_the_format');
  });

  it("the largest it offers is the largest it can verify", () => {
    expect(typeof magicSquareCandidate(1n, LARGEST_VERIFIABLE_SIZE)).toBe('object');
    expect(typeof magicSquareCandidate(1n, LARGEST_VERIFIABLE_SIZE + 1)).toBe('string');
  });
});

describe("a batch", () => {
  it("every board it returns is accepted by the contract", () => {
    let boards = 0;
    for (const size of [3, 4, 5]) {
      const batch = generateMagicSquareBatch(
        { size, count: 2, firstSeed: 1n },
        COPY,
      );

      expect(batch.report.exhausted, `size ${size}`).toBe(false);
      for (const board of batch.boards) {
        expect(parsePuzzle(board), `size ${size}`).toBeNull();
        expect(board.kind).toBe('magicSquare');
      }
      boards += batch.boards.length;
    }
    console.log(`  magic square generator · ${boards} boards, all accepted by parsePuzzle`);
    expect(boards).toBe(6);
  }, 300_000);

  it("a size it cannot verify exhausts the budget, named", () => {
    const batch = generateMagicSquareBatch(
      { size: 6, count: 1, firstSeed: 1n },
      COPY,
    );

    expect(batch.boards).toEqual([]);
    expect(batch.report.exhausted).toBe(true);
    expect(batch.report.refused).toHaveProperty('size_not_verifiable', ATTEMPTS_PER_BOARD);
  });

  it("the same request is the same boards", () => {
    const request = { size: 3, count: 2, firstSeed: 9n } as const;
    expect(generateMagicSquareBatch(request, COPY).boards).toEqual(
      generateMagicSquareBatch(request, COPY).boards,
    );
  });

  it("different seeds are different boards", () => {
    const a = generateMagicSquareBatch({ size: 3, count: 1, firstSeed: 9n }, COPY);
    const b = generateMagicSquareBatch({ size: 3, count: 1, firstSeed: 900n }, COPY);
    expect(a.boards).not.toEqual(b.boards);
  });
});
