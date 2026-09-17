import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  REFERENCE_SHEET_LINES,
  referenceSheetFor,
  type BuildableKind,
} from "../src/adapters/build-puzzles.js";
import { AUTHORED_PACK_PATH } from "./authored-pack.js";

/**
 * The reference sheet a player opens mid-board.
 *
 * **Two copies of the same words, and this is what stops them drifting.** The
 * generator writes a sheet into every board it produces; the boards that ship
 * are pasted from it into `app/assets/packs/starter.json`, which is where the
 * app reads them and where `build:pack` reads them again. Nothing connected
 * those two until this file: the first KenKen in the shipped pack carried a
 * sheet the generator has never produced, and it was the one a player hit
 * first.
 *
 * The structural assertions below are the defects that sheet had, each turned
 * into a question the copy has to answer — it never stated the objective, it
 * explained `-` and not `+`, and it used *jaula* without ever saying what one
 * looks like.
 */

/** Every board in the pack the app bundles, with the size it was drawn at. */
interface AuthoredBoard {
  readonly kind: BuildableKind;
  readonly size: number;
  readonly referenceSheet: readonly string[];
}

interface RawPuzzle {
  readonly kind: string;
  readonly payload: {
    readonly board?: { readonly size: number };
    readonly grid?: readonly string[];
  };
  readonly reference_sheet: readonly string[];
}

function authoredBoards(): readonly AuthoredBoard[] {
  const raw: { readonly puzzles: readonly RawPuzzle[] } = JSON.parse(
    readFileSync(AUTHORED_PACK_PATH, "utf8"),
  );
  return raw.puzzles.map((puzzle) => ({
    kind: puzzle.kind as BuildableKind,
    size: puzzle.payload.board?.size ?? puzzle.payload.grid?.length ?? 0,
    referenceSheet: puzzle.reference_sheet,
  }));
}

/**
 * The characters a KenKen cage can print in its corner.
 *
 * Taken from the renderer rather than from the rules: `puzzle_board_view.dart`
 * draws `'${target}${operation}'`, so these are literally what a player sees —
 * including the **ASCII hyphen**, which the sheet that shipped spelled as the
 * minus sign U+2212.
 */
const CAGE_OPERATORS = ["+", "-", "×", "÷"] as const;

/** Every kind, at a size it is actually drawn at somewhere. */
const KINDS: readonly BuildableKind[] = [
  "kenken",
  "killer",
  "magicSquare",
  "kakuro",
  "wordSearch",
];

describe("the reference sheet", () => {
  it("says the same thing everywhere it is written down, over a board list asserted non-empty", () => {
    const boards = authoredBoards();
    expect(boards.length).toBeGreaterThan(0);

    const drifted = boards.filter(
      (board) =>
        JSON.stringify(board.referenceSheet) !==
        JSON.stringify(referenceSheetFor(board.kind, board.size)),
    );

    expect(
      drifted.map((board) => `${board.kind} ${board.size}: ${board.referenceSheet[0]}`),
    ).toEqual([]);
    // eslint-disable-next-line no-console
    console.log(`  reference sheets · ${boards.length} shipped boards agree with the generator`);
  });

  it("is three lines everywhere, so the card has one shape", () => {
    for (const kind of KINDS) {
      for (const size of [3, 4, 5, 6]) {
        expect(referenceSheetFor(kind, size)).toHaveLength(REFERENCE_SHEET_LINES);
      }
    }
  });

  it("states the objective in its first line", () => {
    for (const kind of KINDS) {
      expect(referenceSheetFor(kind, 4)[0]).toMatch(/^(Llena|Encuentra)\b/u);
    }
  });

  it("names the range a board of that size takes: a magic square runs to its cell count, and kakuro is nine digits whatever it measures", () => {
    expect(referenceSheetFor("kenken", 3)[0]).toContain("del 1 al 3");
    expect(referenceSheetFor("kenken", 5)[0]).toContain("del 1 al 5");
    expect(referenceSheetFor("killer", 4)[0]).toContain("del 1 al 4");
    expect(referenceSheetFor("magicSquare", 3)[0]).toContain("del 1 al 9");
    expect(referenceSheetFor("magicSquare", 4)[0]).toContain("del 1 al 16");
    expect(referenceSheetFor("kakuro", 6)[0]).toContain("del 1 al 9");
  });

  it("explains every operator a KenKen cage can carry, not only the minus", () => {
    const vocabulary = referenceSheetFor("kenken", 4)[1];
    for (const operator of CAGE_OPERATORS) {
      expect(vocabulary).toContain(operator);
    }
  });

  it("says what a jaula looks like before using the word", () => {
    for (const kind of ["kenken", "killer"] as const) {
      const sheet = referenceSheetFor(kind, 4);
      const introduction = sheet.find((line) => line.includes("jaula"));
      expect(introduction, `${kind} never says jaula`).toBeDefined();
      expect(introduction).toContain("punteado");
    }
  });

  it("never leaves a line the card cannot show at a glance", () => {
    for (const kind of KINDS) {
      for (const line of referenceSheetFor(kind, 6)) {
        expect(line.length, `${kind}: ${line}`).toBeLessThanOrEqual(150);
      }
    }
  });
});
