/**
 * `cagedCandidate` on its own, held to what its cages claim.
 *
 * The batch cannot catch any of this. A wrong target is refused by the
 * contract, the seed is dropped, and the batch still returns the boards it
 * asked for — so proposing a bad label is not unsafe, it is a silent collapse
 * in hit rate, which is worse to diagnose. Only a direct assertion separates a
 * correct labeller from one that is wrong half the time.
 *
 * The labeller carries no guard against a difference of zero, and that is
 * deliberate: a pair is a cell and an orthogonal neighbour, so it shares a row
 * or a column, and a Latin square repeats no digit along either. It is
 * asserted rather than assumed, because the day `grow` stops annexing
 * *neighbours* the labeller starts emitting an off-schema target.
 *
 * Order is part of the payload. The pack is byte-diffed, so a payload whose
 * shape depended on draw order would make an unrelated regeneration look like
 * a content change.
 */

import { describe, expect, it } from "vitest";

import { cagedCandidate } from "../../src/puzzles/caged.js";

interface Cell {
  readonly row: number;
  readonly col: number;
}

interface Board {
  readonly size: number;
  readonly blocked: readonly Cell[];
  readonly given: readonly Cell[];
  readonly solution: readonly (readonly number[])[];
}

interface KenKenPayload {
  readonly board: Board;
  readonly cages: readonly {
    readonly cells: readonly Cell[];
    readonly operation: "+" | "-" | "×" | "÷";
    readonly target: number;
  }[];
}

interface KillerPayload {
  readonly board: Board;
  readonly cages: readonly { readonly cells: readonly Cell[]; readonly target: number }[];
}

const kenken = (seed: number, size = 5): KenKenPayload =>
  cagedCandidate("kenken", BigInt(seed), size)!.payload as unknown as KenKenPayload;

const valuesOf = (board: Board, cells: readonly Cell[]): number[] =>
  cells.map((cell) => board.solution[cell.row]![cell.col]!);

/** What the cage claims, computed from the solution rather than from the cage. */
function applied(operation: string, values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => b - a);
  switch (operation) {
    case "+":
      return values.reduce((a, b) => a + b, 0);
    case "×":
      return values.reduce((a, b) => a * b, 1);
    case "-":
      return sorted[0]! - sorted[1]!;
    default:
      return sorted[0]! / sorted[1]!;
  }
}

const SEEDS = Array.from({ length: 60 }, (_, i) => i + 1);

/** Every supported size, so a rule that only holds at one of them is caught. */
const SIZES = [3, 4, 5, 6] as const;

const everyCage = function* (): Generator<{
  readonly seed: number;
  readonly size: number;
  readonly payload: KenKenPayload;
  readonly cage: KenKenPayload["cages"][number];
  readonly values: readonly number[];
}> {
  for (const size of SIZES) {
    for (const seed of SEEDS) {
      const payload = kenken(seed, size);
      for (const cage of payload.cages) {
        yield { seed, size, payload, cage, values: valuesOf(payload.board, cage.cells) };
      }
    }
  }
};

/**
 * The smaller value of every quotient cage the sweep saw.
 *
 * `a ÷ b` and `a × b` are the same number when `b` is 1, and almost every
 * divisible pair in a small Latin square contains a 1 — so a sweep that
 * happened to see only those would pass for a labeller that multiplied.
 * PROC-10: the case has to be present, not hoped for.
 */
const quotientDivisors = (): number[] =>
  [...everyCage()]
    .filter(({ cage }) => cage.operation === "÷")
    .map(({ values }) => Math.min(...values));

/**
 * Which cage each of the board's two printed cells belongs to.
 *
 * Two givens inside one cage pin the cage rather than the board, which is most
 * of the reason an authored magic square was once refused as
 * `solution_not_unique`. Distinct *cells* is not the same property, and a
 * picker that always chose the same cage would satisfy that one.
 */
function cagesOfThePrintedCells(payload: KenKenPayload): number[] {
  return payload.board.given.map((cell) =>
    payload.cages.findIndex((cage) =>
      cage.cells.some((c) => c.row === cell.row && c.col === cell.col),
    ),
  );
}

/**
 * Two neighbouring seeds' candidates, serialized.
 *
 * The square, the cages and the labels are drawn off derived seeds rather than
 * one stream: three decisions off one stream would each be a function of the
 * ones before it. The observable consequence — two seeds sharing a square do
 * not share a partition — cannot be asserted directly, so what is asserted is
 * the weaker thing that would break first: neighbouring seeds are unrelated.
 */
const neighbouringSeeds = (): readonly [string, string] => [
  JSON.stringify(cagedCandidate("kenken", 100n, 5)),
  JSON.stringify(cagedCandidate("kenken", 101n, 5)),
];

describe("a KenKen cage says what its cells actually do", () => {
  it("every target is the operation applied to the solution", () => {
    for (const { seed, size, cage, values } of everyCage()) {
      expect(cage.target, `${size}×${size} seed ${seed}: ${cage.operation} over ${values}`).toBe(
        applied(cage.operation, values),
      );
    }
  }, 120_000);

  it("a quotient by something other than one is among the cases checked", () => {
    expect(quotientDivisors().filter((b) => b > 1).length).toBeGreaterThan(0);
  }, 120_000);

  it("a one-cell cage prints its value with a plus", () => {
    for (const seed of SEEDS) {
      const payload = kenken(seed);
      for (const cage of payload.cages.filter((c) => c.cells.length === 1)) {
        expect(cage.operation).toBe("+");
        expect(cage.target).toBe(valuesOf(payload.board, cage.cells)[0]);
      }
    }
  });

  it("a difference or a quotient is only ever offered on a pair", () => {
    for (const { cage } of everyCage()) {
      if (cage.operation === "-" || cage.operation === "÷") {
        expect(cage.cells).toHaveLength(2);
      }
    }
  }, 120_000);

  it("a two-cell cage never holds the same digit twice", () => {
    for (const { cage, values } of everyCage()) {
      if (cage.cells.length === 2) {
        expect(new Set(values).size).toBe(2);
      }
    }
  }, 120_000);

  it("a target is always at least one, as KenKenPayloadSchema requires", () => {
    for (const seed of SEEDS) {
      for (const cage of kenken(seed).cages) {
        expect(cage.target).toBeGreaterThanOrEqual(1);
      }
    }
  });

  it("a quotient divides exactly", () => {
    for (const seed of SEEDS) {
      const payload = kenken(seed);
      for (const cage of payload.cages.filter((c) => c.operation === "÷")) {
        expect(Number.isInteger(cage.target)).toBe(true);
      }
    }
  });

  it("all four operations get used, or the option list is dead code", () => {
    const seen = new Set([...everyCage()].map(({ cage }) => cage.operation));
    expect([...seen].sort()).toEqual(["+", "-", "×", "÷"].sort());
  }, 120_000);
});

describe("a Killer cage is a sum of distinct digits", () => {
  it("every target is the sum, and no cage repeats a digit", () => {
    let boards = 0;
    for (const seed of SEEDS) {
      const candidate = cagedCandidate("killer", BigInt(seed), 5);
      if (candidate === null) {
        continue;
      }
      boards += 1;
      const payload = candidate.payload as unknown as KillerPayload;
      for (const cage of payload.cages) {
        const values = valuesOf(payload.board, cage.cells);
        expect(new Set(values).size).toBe(values.length);
        expect(cage.target).toBe(values.reduce((a, b) => a + b, 0));
      }
    }
    expect(boards, 'every seed produced null, so nothing above ran').toBeGreaterThan(0);
  });

  it("a cage carries no operation", () => {
    const candidate = SEEDS.map((s) => cagedCandidate("killer", BigInt(s), 4)).find(
      (c) => c !== null,
    )!;
    const payload = candidate.payload as unknown as KillerPayload;
    for (const cage of payload.cages) {
      expect(cage).not.toHaveProperty("operation");
    }
  });
});

describe("the board the cages describe", () => {
  it("the cages partition it exactly", () => {
    for (const seed of SEEDS) {
      const payload = kenken(seed);
      const cells = payload.cages.flatMap((cage) => cage.cells);

      expect(cells).toHaveLength(25);
      expect(new Set(cells.map((c) => `${c.row},${c.col}`)).size).toBe(25);
    }
  });

  it("nothing is blocked — a caged board has no holes", () => {
    expect(kenken(1).board.blocked).toEqual([]);
  });

  it("it prints two cells, distinct and inside the board", () => {
    for (const seed of SEEDS) {
      const payload = kenken(seed);
      const given = payload.board.given;

      expect(given, `seed ${seed}`).toHaveLength(2);
      expect(new Set(given.map((c) => `${c.row},${c.col}`)).size, `seed ${seed}`).toBe(2);
      for (const cell of given) {
        expect(cell.row).toBeLessThan(5);
        expect(cell.col).toBeLessThan(5);
      }
    }
  });

  it("the two printed cells come from different cages", () => {
    for (const size of SIZES) {
      for (const seed of SEEDS) {
        const cages = cagesOfThePrintedCells(kenken(seed, size));

        expect(new Set(cages).size, `${size}×${size} seed ${seed}`).toBe(cages.length);
      }
    }
  }, 120_000);

  it("the printed cells come in a stable order", () => {
    for (const seed of SEEDS) {
      const given = kenken(seed).board.given;
      const sorted = [...given].sort((a, b) => a.row - b.row || a.col - b.col);
      expect(given).toEqual(sorted);
    }
  });

  it("the solution is the size it claims", () => {
    for (const size of [3, 4, 6]) {
      const payload = cagedCandidate("kenken", 9n, size)!.payload as unknown as KenKenPayload;
      expect(payload.board.size).toBe(size);
      expect(payload.board.solution).toHaveLength(size);
      for (const row of payload.board.solution) {
        expect(row).toHaveLength(size);
      }
    }
  });
});

describe("a candidate is a function of its seed", () => {
  it("the same seed is the same candidate", () => {
    expect(cagedCandidate("kenken", 12n, 5)).toEqual(cagedCandidate("kenken", 12n, 5));
  });

  it("the square, the cages and the labels do not move together", () => {
    const [a, b] = neighbouringSeeds();

    expect(a).not.toBe(b);
  });
});
