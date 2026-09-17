import { describe, expect, it } from "vitest";

import { cagePartition, MAX_CAGE_CELLS, type CageCells } from "../../src/puzzles/cages.js";

const key = (cell: { row: number; col: number }): string => `${cell.row},${cell.col}`;

/**
 * Whether a cage is one shape: every cell reachable from the first by
 * orthogonal steps.
 *
 * A cage drawn in two pieces cannot be outlined, and would read as two cages
 * sharing a number.
 */
function isConnected(cage: CageCells): boolean {
  const remaining = new Set(cage.map(key));
  const queue = [cage[0]!];
  remaining.delete(key(cage[0]!));
  while (queue.length > 0) {
    const at = queue.pop()!;
    for (const [dr, dc] of [
      [0, 1],
      [0, -1],
      [1, 0],
      [-1, 0],
    ] as const) {
      const next = { row: at.row + dr, col: at.col + dc };
      if (remaining.delete(key(next))) {
        queue.push(next);
      }
    }
  }
  return remaining.size === 0;
}

/**
 * The rows and the columns that some multi-cell cage reaches, over twenty
 * seeds.
 *
 * A growth rule that refused one direction — `row <= 0` instead of `row < 0`,
 * say — still partitions the board and still keeps every cage connected. What
 * it does is turn the first row into singletons, which is a row of printed
 * answers, and nothing else here would notice.
 */
function linesGrownCagesReach(size: number): {
  readonly rows: ReadonlySet<number>;
  readonly columns: ReadonlySet<number>;
} {
  const rows = new Set<number>();
  const columns = new Set<number>();

  for (let seed = 0; seed < 20; seed += 1) {
    for (const cage of cagePartition(BigInt(seed), size)) {
      if (cage.length === 1) {
        continue;
      }
      for (const cell of cage) {
        rows.add(cell.row);
        columns.add(cell.col);
      }
    }
  }

  return { rows, columns };
}

/**
 * Every step from one cell of a cage to an orthogonal neighbour in the same
 * cage — which is what a direction is here, growth leaving no other trace.
 *
 * Two directions that were secretly the same direction would leave every other
 * assertion true and make every cage a bar.
 */
function stepsWithinCages(size: number): ReadonlySet<string> {
  const steps = new Set<string>();

  for (let seed = 0; seed < 20; seed += 1) {
    for (const cage of cagePartition(BigInt(seed), size)) {
      for (const a of cage) {
        for (const b of cage) {
          if (Math.abs(a.row - b.row) + Math.abs(a.col - b.col) === 1) {
            steps.add(`${b.row - a.row},${b.col - a.col}`);
          }
        }
      }
    }
  }

  return steps;
}

describe("a partition covers the board exactly once", () => {
  it("every cell is in one cage, at every supported size", () => {
    for (let size = 3; size <= 6; size += 1) {
      const cages = cagePartition(99n, size);
      const seen = cages.flat().map(key);

      expect(new Set(seen).size, `size ${size}`).toBe(size * size);
      expect(seen, `size ${size}`).toHaveLength(size * size);
    }
  });

  it("no cell is outside the board", () => {
    const size = 5;
    for (const cell of cagePartition(3n, size).flat()) {
      expect(cell.row).toBeGreaterThanOrEqual(0);
      expect(cell.col).toBeGreaterThanOrEqual(0);
      expect(cell.row).toBeLessThan(size);
      expect(cell.col).toBeLessThan(size);
    }
  });
});

describe("a cage is one shape a player can see", () => {
  it("every cage is orthogonally connected", () => {
    for (let size = 3; size <= 6; size += 1) {
      for (let seed = 0; seed < 8; seed += 1) {
        for (const cage of cagePartition(BigInt(seed), size)) {
          expect(isConnected(cage), `size ${size} seed ${seed}: ${cage.map(key)}`).toBe(true);
        }
      }
    }
  });

  it("no cage is empty and none exceeds the bound", () => {
    for (const cage of cagePartition(11n, 6)) {
      expect(cage.length).toBeGreaterThanOrEqual(1);
      expect(cage.length).toBeLessThanOrEqual(MAX_CAGE_CELLS);
    }
  });

  it("the board is not one cage per cell, which would print every answer", () => {
    const cages = cagePartition(5n, 5);
    expect(cages.some((cage) => cage.length > 1)).toBe(true);
  });
});

describe("growth reaches the whole board", () => {
  it("a multi-cell cage touches every row and every column", () => {
    const { rows, columns } = linesGrownCagesReach(5);

    expect([...rows].sort()).toEqual([0, 1, 2, 3, 4]);
    expect([...columns].sort()).toEqual([0, 1, 2, 3, 4]);
  });

  it("cages grow in all four directions", () => {
    expect([...stepsWithinCages(5)].sort()).toEqual(["-1,0", "0,-1", "0,1", "1,0"]);
  });
});

describe("a board too small to partition is refused", () => {
  it("below three", () => {
    expect(() => cagePartition(1n, 2)).toThrow(RangeError);
    expect(() => cagePartition(1n, 2)).toThrow(/below 3/);
  });
});

describe("the partition is seeded", () => {
  it("the same seed is the same partition", () => {
    expect(cagePartition(42n, 4)).toEqual(cagePartition(42n, 4));
  });

  it("different seeds differ", () => {
    const seen = new Set(
      Array.from({ length: 12 }, (_, i) => JSON.stringify(cagePartition(BigInt(i), 4))),
    );
    expect(seen.size).toBeGreaterThan(1);
  });
});
