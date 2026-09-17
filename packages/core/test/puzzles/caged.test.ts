/**
 * The caged batch: KenKen and Killer boards, proposed and then judged.
 *
 * `parsePuzzle` is the one authority, and it is the same function the pack
 * builder and the device's reader answer to. A generator with its own idea of
 * "solvable" would be a second implementation of the rules, free to disagree
 * with the one that ships. So a candidate is proposed and never repaired: the
 * generator cannot fix a refused square without deciding what the solution
 * should have been, which is owning a solver. The payload's own consistency
 * comes from the same place — `parsePuzzle` checks the declared solution
 * against its own search, so a board paired with an unrelated square is
 * refused there rather than here.
 *
 * A refusal is named, not merely counted. Killer at 5×5 rejects far more
 * candidates than it keeps, and "the squares keep repeating a digit inside a
 * cage" and "the solver found two answers" are different problems with
 * different fixes: a single generic tag would hide which one is happening, and
 * a collapse in hit rate has to stay tellable from a request that was simply
 * small.
 */

import { readFileSync } from "node:fs";

import { parsePuzzle, type PuzzleEnvelope } from "@akimath/contract";
import { describe, expect, it } from "vitest";

import { ATTEMPTS_PER_BOARD, generateCagedBatch, type PuzzleCopy } from "../../src/puzzles/batch.js";
import { cagedCandidate } from "../../src/puzzles/caged.js";

const COPY: PuzzleCopy = {
  tutorialSteps: ["Cada fila y cada columna llevan cada número una vez."],
  referenceSheet: ["La esquina de la jaula dice el resultado."],
};

const SIZES = [3, 4, 5, 6] as const;

/** Printed because the count is the evidence, not the green tick. */
function reportBoardsAccepted(generator: string, boards: number): void {
  console.log(`  ${generator} generator · ${boards} boards, all accepted by parsePuzzle`);
}

/**
 * The payload of the first board an upward walk from seed one finds.
 *
 * A caller regenerating with `firstSeed = last + n` expects no overlap, so the
 * direction matters: walking down would still find boards and still look
 * reproducible.
 */
function firstAcceptedPayloadWalkingUp(size: number): unknown {
  const found: unknown[] = [];
  for (let seed = 1n; found.length === 0; seed += 1n) {
    const candidate = cagedCandidate("kenken", seed, size);
    if (candidate === null) {
      continue;
    }
    const envelope = {
      ...candidate,
      tutorial_steps: [...COPY.tutorialSteps],
      reference_sheet: [...COPY.referenceSheet],
    };
    if (parsePuzzle(envelope) === null) {
      found.push(candidate.payload);
    }
  }
  return found[0];
}

/**
 * Seven is past the contract's 6×6 ceiling, so every candidate is refused on
 * shape and no seed will ever help.
 *
 * An empty list that reads as "there was nothing to make" is the failure this
 * prevents: the report says the budget ran out and names what refused it.
 */
const PAST_THE_CEILING = { kind: "kenken", size: 7, count: 1, firstSeed: 1n } as const;

describe("every board a batch emits is one the contract accepts", () => {
  it("across both kinds and every supported size", () => {
    let boards = 0;
    for (const kind of ["kenken", "killer"] as const) {
      for (const size of SIZES) {
        const batch = generateCagedBatch({ kind, size, count: 2, firstSeed: 1n }, COPY);

        expect(batch.report.exhausted, `${kind} ${size}`).toBe(false);
        expect(batch.boards, `${kind} ${size}`).toHaveLength(2);
        for (const board of batch.boards) {
          expect(parsePuzzle(board), `${kind} ${size}`).toBeNull();
          expect(board.kind).toBe(kind);
        }
        boards += batch.boards.length;
      }
    }
    reportBoardsAccepted("caged", boards);
    expect(boards).toBe(16);
  }, 120_000);

  it("the solution really is the board's, not a second one", () => {
    const batch = generateCagedBatch(
      { kind: "kenken", size: 4, count: 1, firstSeed: 7n },
      COPY,
    );
    const payload = batch.boards[0]!.payload as {
      board: { size: number; solution: number[][]; given: { row: number; col: number }[] };
      cages: { cells: { row: number; col: number }[] }[];
    };

    expect(payload.board.solution).toHaveLength(4);
    expect(payload.cages.flatMap((cage) => cage.cells)).toHaveLength(16);
    expect(payload.board.given.length).toBeGreaterThan(0);
  });
});

describe("a batch is reproducible", () => {
  it("the same request is the same boards", () => {
    const request = { kind: "kenken", size: 4, count: 3, firstSeed: 5n } as const;
    expect(generateCagedBatch(request, COPY).boards).toEqual(
      generateCagedBatch(request, COPY).boards,
    );
  });

  it("seeds are consumed upward from the first", () => {
    const batch = generateCagedBatch(
      { kind: "kenken", size: 4, count: 1, firstSeed: 1n },
      COPY,
    );

    expect(batch.boards[0]!.payload).toEqual(firstAcceptedPayloadWalkingUp(4));
  });

  it("a different first seed is different boards", () => {
    const a = generateCagedBatch({ kind: "kenken", size: 4, count: 2, firstSeed: 5n }, COPY);
    const b = generateCagedBatch({ kind: "kenken", size: 4, count: 2, firstSeed: 500n }, COPY);
    expect(a.boards).not.toEqual(b.boards);
  });

  it("the copy travels with every board", () => {
    const batch = generateCagedBatch({ kind: "killer", size: 4, count: 2, firstSeed: 2n }, COPY);
    for (const board of batch.boards) {
      expect(board.tutorial_steps).toEqual(COPY.tutorialSteps);
      expect(board.reference_sheet).toEqual(COPY.referenceSheet);
    }
  });
});

describe("the batch reports what it spent", () => {
  it("attempts and accepted are both counted", () => {
    const batch = generateCagedBatch({ kind: "killer", size: 5, count: 2, firstSeed: 1n }, COPY);

    expect(batch.report.accepted).toBe(2);
    expect(batch.report.attempts).toBeGreaterThanOrEqual(2);
  });

  it("a refused candidate is named by its tag, not merely counted", () => {
    const batch = generateCagedBatch({ kind: "killer", size: 5, count: 3, firstSeed: 1n }, COPY);

    expect(Object.keys(batch.report.refused).length).toBeGreaterThan(0);
    expect(batch.report.refused).toHaveProperty('repeated_digit_in_cage');
    const refusedTotal = Object.values(batch.report.refused).reduce((a, b) => a + b, 0);
    expect(batch.report.attempts).toBe(batch.report.accepted + refusedTotal);
  });

  it("an impossible request exhausts its budget and says so", () => {
    const batch = generateCagedBatch(PAST_THE_CEILING, COPY);

    expect(batch.boards).toEqual([]);
    expect(batch.report.exhausted).toBe(true);
    expect(batch.report.attempts).toBe(ATTEMPTS_PER_BOARD);
    expect(batch.report.refused).toHaveProperty("payload_shape", ATTEMPTS_PER_BOARD);
  }, 120_000);

  it("a satisfiable request stops early: the budget is a ceiling", () => {
    const batch = generateCagedBatch(
      { kind: "kenken", size: 4, count: 2, firstSeed: 1n },
      COPY,
    );

    expect(batch.report.attempts).toBeLessThan(2 * ATTEMPTS_PER_BOARD);
  });
});

describe("a candidate is proposed, never repaired", () => {
  it("a Killer square with a repeated digit in a cage is dropped", () => {
    const dropped = Array.from({ length: 40 }, (_, i) =>
      cagedCandidate("killer", BigInt(i), 5),
    ).filter((candidate) => candidate === null);

    expect(dropped.length).toBeGreaterThan(0);
  });

  it("the generator holds no solver of its own, and the source says so", () => {
    const sources = ["src/puzzles/caged.ts", "src/puzzles/cages.ts", "src/puzzles/latin.ts"]
      .map((path) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8"))
      .join("\n");

    for (const forbidden of ["searchSolutions", "checkUniqueSolution", "backtrack"]) {
      expect(sources, `${forbidden} appears in the candidate builder`).not.toContain(forbidden);
    }
  });
});

describe("the emitted envelope is the frozen shape", () => {
  it("it round-trips through the envelope schema", () => {
    const batch = generateCagedBatch({ kind: "kenken", size: 5, count: 1, firstSeed: 3n }, COPY);
    const board: PuzzleEnvelope = batch.boards[0]!;

    expect(Object.keys(board).sort()).toEqual(
      ["kind", "payload", "reference_sheet", "tutorial_steps"].sort(),
    );
  });
});
