import { parsePuzzle } from "@akimath/contract";
import { describe, expect, it } from "vitest";

import { generateWordSearchBatch, type PuzzleCopy } from "../../src/puzzles/batch.js";
import { wordSearchCandidate, type WordSearchCandidate } from "../../src/puzzles/word-search.js";

const WORDS = ["SUMA", "RESTA", "CERO", "DOBLE", "MITAD", "NUMERO", "DECENA", "UNIDAD"];

const DIRECTIONS: readonly (readonly [number, number])[] = [
  [0, 1],
  [0, -1],
  [1, 0],
  [-1, 0],
  [1, 1],
  [1, -1],
  [-1, 1],
  [-1, -1],
];

/**
 * How many times a word reads out of the grid, over all eight directions.
 *
 * Twice is a rejection in the contract, not a warning: two placements make two
 * different traces correct and the puzzle stops having an answer.
 */
function occurrences(grid: readonly (readonly string[])[], word: string): number {
  let found = 0;
  for (const [row, letters] of grid.entries()) {
    for (const col of letters.keys()) {
      for (const [dr, dc] of DIRECTIONS) {
        if ([...word].every((letter, i) => grid[row + dr * i]?.[col + dc * i] === letter)) {
          found += 1;
        }
      }
    }
  }
  return found;
}

const grids = (candidate: WordSearchCandidate): readonly (readonly string[])[] =>
  candidate.payload.grid;

const SEEDS = Array.from({ length: 40 }, (_, i) => i + 1);

const made = (seed: number, size = 8, words = WORDS): WordSearchCandidate | null =>
  wordSearchCandidate(BigInt(seed), size, words);

/**
 * What an unplaced cell would hold. A placeholder passes the single-letter
 * regex only by accident, and the whole point of the filler is that a player
 * cannot see where the words are.
 */
const UNFILLED_CELL = ".";

/**
 * Six letters in a 6×6: as long as the grid is wide, and so a straight line
 * across it. The bound is `<= size`, not `< size`, because dropping such a
 * word would silently shrink the vocabulary.
 */
const EXACTLY_AS_LONG_AS_THE_GRID = ["MEDIDA", "SUMA"];

/**
 * Six letters against a 3×3: no line of that grid holds it in any of the eight
 * directions. A six-letter word in a 5×5 can still lie along a diagonal, which
 * is why the refusal is shown against the smaller board.
 */
const LONGER_THAN_ANY_LINE = ["UNIDAD"];

/**
 * Two words against a 3×3, both longer than any line of it, so no seed can
 * help. What the report then says is that the proposer declined, not that the
 * contract refused — different problems with different fixes.
 */
const NOTHING_FITS = ["UNIDAD", "DECENA"];

/**
 * How many of the eight words each seed's grid actually hides.
 *
 * Measured over two hundred seeds: 198 place all eight and 2 place seven. The
 * floor and the proportion are both asserted, because the failure this catches
 * is a *collapse* — a generator that only ever started in one corner, or that
 * computed its start cells wrongly, places two or three, and every "each word
 * appears once" assertion still passes, since those only check the words it
 * *claims*.
 */
const wordsPlacedPerSeed = (): readonly number[] =>
  SEEDS.map((s) => made(s)?.payload.words.length ?? 0);

describe("a generated grid hides the words it lists", () => {
  it("every listed word is in the grid exactly once", () => {
    let checked = 0;
    for (const seed of SEEDS) {
      const candidate = made(seed);
      if (candidate === null) {
        continue;
      }
      checked += 1;
      for (const word of candidate.payload.words) {
        expect(occurrences(grids(candidate), word), `seed ${seed}: ${word}`).toBe(1);
      }
    }
    expect(checked, "every seed came back null").toBeGreaterThan(0);
  });

  it("the grid is rectangular and the right size", () => {
    for (const size of [5, 6, 7, 8]) {
      const candidate = SEEDS.map((s) => made(s, size)).find((c) => c !== null)!;
      expect(candidate.payload.grid).toHaveLength(size);
      for (const row of candidate.payload.grid) {
        expect(row).toHaveLength(size);
      }
    }
  });

  it("every cell holds one letter the contract allows", () => {
    const candidate = made(1)!;
    for (const row of candidate.payload.grid) {
      for (const cell of row) {
        expect(cell).toMatch(/^[A-ZÑ]$/u);
      }
    }
  });

  it("no cell is left unfilled", () => {
    const candidate = made(1)!;
    expect(candidate.payload.grid.flat().join("")).not.toContain(UNFILLED_CELL);
  });
});

describe("it uses the whole grid", () => {
  it("an 8×8 hides almost all of eight words, almost always", () => {
    const counts = wordsPlacedPerSeed();

    expect(Math.min(...counts)).toBeGreaterThanOrEqual(7);
    expect(counts.filter((n) => n === 8).length).toBeGreaterThan(SEEDS.length - 5);
  });

  it("words start all over the grid, not in one corner", () => {
    const firstCells = new Set<string>();
    for (const seed of SEEDS) {
      const candidate = made(seed);
      if (candidate === null) {
        continue;
      }
      const grid = grids(candidate);
      for (const word of candidate.payload.words) {
        for (const [row, letters] of grid.entries()) {
          for (const col of letters.keys()) {
            for (const [dr, dc] of DIRECTIONS) {
              if ([...word].every((l, i) => grid[row + dr * i]?.[col + dc * i] === l)) {
                firstCells.add(`${row},${col}`);
              }
            }
          }
        }
      }
    }

    expect(firstCells.size).toBeGreaterThan(20);
  });

  it("a word exactly as long as the grid is wide still fits", () => {
    const candidate = wordSearchCandidate(3n, 6, EXACTLY_AS_LONG_AS_THE_GRID)!;

    expect(candidate.payload.words).toContain("MEDIDA");
  });
});

describe("the contract decides", () => {
  it("the envelope names its kind", () => {
    expect(made(1)!.kind).toBe("wordSearch");
  });

  it("every candidate it returns is accepted", () => {
    let accepted = 0;
    for (const seed of SEEDS) {
      const candidate = made(seed);
      if (candidate === null) {
        continue;
      }
      const tag = parsePuzzle({
        kind: "wordSearch",
        payload: candidate.payload,
        tutorial_steps: ["x"],
        reference_sheet: ["y"],
      });
      expect(tag, `seed ${seed}`).toBeNull();
      accepted += 1;
    }
    expect(accepted).toBeGreaterThan(0);
  });

  it("a word longer than the grid is refused rather than truncated", () => {
    expect(wordSearchCandidate(1n, 3, LONGER_THAN_ANY_LINE)).toBeNull();
  });

  it("more than eight words is trimmed, not proposed off-schema", () => {
    const candidate = wordSearchCandidate(1n, 8, [...WORDS, "PARES", "IMPAR"]);
    expect(candidate?.payload.words.length).toBeLessThanOrEqual(8);
  });

  it("an empty vocabulary makes nothing", () => {
    expect(wordSearchCandidate(1n, 6, [])).toBeNull();
  });
});

describe("it is a function of its seed", () => {
  it("the same seed is the same grid", () => {
    expect(made(9)).toEqual(made(9));
  });

  it("different seeds differ", () => {
    const seen = new Set(SEEDS.map((s) => JSON.stringify(made(s))));
    expect(seen.size).toBeGreaterThan(1);
  });

  it("words run in more than one direction, or the grid is a word list", () => {
    const steps = new Set<string>();
    for (const seed of SEEDS) {
      const candidate = made(seed);
      if (candidate === null) {
        continue;
      }
      const grid = grids(candidate);
      for (const word of candidate.payload.words) {
        for (const [row, letters] of grid.entries()) {
          for (const col of letters.keys()) {
            for (const [dr, dc] of DIRECTIONS) {
              if ([...word].every((l, i) => grid[row + dr * i]?.[col + dc * i] === l)) {
                steps.add(`${dr},${dc}`);
              }
            }
          }
        }
      }
    }
    expect(steps.size).toBeGreaterThan(2);
  });
});

describe("a batch of them", () => {
  const COPY: PuzzleCopy = {
    tutorialSteps: ["Arrastra el dedo de la primera letra a la última."],
    referenceSheet: ["Las palabras se leen en línea recta."],
  };

  it("every board it returns is accepted, and the copy travels", () => {
    const batch = generateWordSearchBatch(
      { size: 8, count: 3, firstSeed: 1n, vocabulary: WORDS },
      COPY,
    );

    expect(batch.report.exhausted).toBe(false);
    expect(batch.boards).toHaveLength(3);
    for (const board of batch.boards) {
      expect(parsePuzzle(board)).toBeNull();
      expect(board.kind).toBe("wordSearch");
      expect(board.tutorial_steps).toEqual(COPY.tutorialSteps);
    }
  });

  it("a vocabulary nothing fits exhausts the budget, named", () => {
    const batch = generateWordSearchBatch(
      { size: 3, count: 1, firstSeed: 1n, vocabulary: NOTHING_FITS },
      COPY,
    );

    expect(batch.boards).toEqual([]);
    expect(batch.report.exhausted).toBe(true);
    expect(batch.report.refused).toHaveProperty("no_word_fits_the_grid");
  }, 60_000);

  it("the same request is the same boards", () => {
    const request = { size: 7, count: 2, firstSeed: 4n, vocabulary: WORDS } as const;
    expect(generateWordSearchBatch(request, COPY).boards).toEqual(
      generateWordSearchBatch(request, COPY).boards,
    );
  });
});
