import { z } from "zod";

import type { PuzzleRejectionTag } from "./rejection.js";

/**
 * The board every numeric puzzle shares. 6×6 is the ceiling and the 9×9 tab
 * split is out of scope (plan §5.3 D15), which is also what makes the
 * uniqueness search in `uniqueness.ts` affordable.
 *
 * A blocked cell carries `0` in the solution. The alternative — a nullable
 * cell — buys a second empty value to get wrong on the Dart side of the seam.
 */
export const CellSchema = z.strictObject({
  row: z.int().min(0),
  col: z.int().min(0),
});

export type Cell = z.infer<typeof CellSchema>;

export const BoardSchema = z.strictObject({
  size: z.int().min(3).max(6),
  blocked: z.array(CellSchema),
  given: z.array(CellSchema),
  solution: z.array(z.array(z.int().min(0))),
});

export type Board = z.infer<typeof BoardSchema>;

export const EMPTY_CELL = 0;

export function cellKey(cell: Cell): string {
  return `${cell.row},${cell.col}`;
}

function isInsideBoard(cell: Cell, size: number): boolean {
  return cell.row < size && cell.col < size;
}

function blockedKeys(board: Board): ReadonlySet<string> {
  return new Set(board.blocked.map(cellKey));
}

export function fillableCells(board: Board): readonly Cell[] {
  const blocked: ReadonlySet<string> = blockedKeys(board);
  const cells: Cell[] = [];
  for (let row = 0; row < board.size; row += 1) {
    for (let col = 0; col < board.size; col += 1) {
      const cell: Cell = { row, col };
      if (!blocked.has(cellKey(cell))) {
        cells.push(cell);
      }
    }
  }
  return cells;
}

export function checkBlockedCells(board: Board): PuzzleRejectionTag | null {
  const strays: boolean = board.blocked.some((cell) => !isInsideBoard(cell, board.size));
  return strays ? "blocked_cell_outside_board" : null;
}

/**
 * A given is a cell whose value is already printed on the board. It has to be
 * a cell the player can see and not one the board blanked out.
 */
export function checkGivenCells(board: Board): PuzzleRejectionTag | null {
  const blocked: ReadonlySet<string> = blockedKeys(board);
  const strays: boolean = board.given.some(
    (cell) => !isInsideBoard(cell, board.size) || blocked.has(cellKey(cell)),
  );
  return strays ? "given_cell_outside_board" : null;
}

/** Every fillable cell belongs to at least one group — kakuro's runs cross. */
export function checkRunCoverage(
  board: Board,
  runs: readonly CageCells[],
): PuzzleRejectionTag | null {
  const covered = new Set<string>();
  for (const run of runs) {
    for (const cell of run.cells) {
      if (!isInsideBoard(cell, board.size)) {
        return "cage_cell_outside_board";
      }
      covered.add(cellKey(cell));
    }
  }
  const complete: boolean = fillableCells(board).every((cell) => covered.has(cellKey(cell)));
  return complete ? null : "cage_coverage_incomplete";
}

export interface BoardLine {
  readonly row: readonly Cell[];
  readonly column: readonly Cell[];
}

/**
 * The board's rows and columns, paired by index. Both the Latin rule and the
 * magic square's targets walk them, and they walked them separately until
 * jscpd said so.
 */
export function boardLines(size: number): readonly BoardLine[] {
  return Array.from({ length: size }, (_unused, index) => {
    const row: Cell[] = [];
    const column: Cell[] = [];
    for (let offset = 0; offset < size; offset += 1) {
      row.push({ row: index, col: offset });
      column.push({ row: offset, col: index });
    }
    return { row, column };
  });
}

/** The digits a board of this reach allows, smallest first. */
export function digitsUpTo(max: number): readonly number[] {
  return Array.from({ length: max }, (_unused, index) => index + 1);
}

/** Runs the checks in order and reports the first thing wrong. */
export function firstRejection(
  checks: readonly (() => PuzzleRejectionTag | null)[],
): PuzzleRejectionTag | null {
  for (const check of checks) {
    const rejection: PuzzleRejectionTag | null = check();
    if (rejection !== null) {
      return rejection;
    }
  }
  return null;
}

/**
 * The declared solution has to be the board's own dimensions, hold a digit the
 * board allows in every fillable cell, and hold nothing in a blocked one.
 */
export function checkSolutionShape(board: Board, domainMax: number): PuzzleRejectionTag | null {
  if (board.solution.length !== board.size) {
    return "solution_shape";
  }
  const blocked: ReadonlySet<string> = blockedKeys(board);
  for (const [row, values] of board.solution.entries()) {
    if (values.length !== board.size) {
      return "solution_shape";
    }
    for (const [col, value] of values.entries()) {
      const expectedEmpty: boolean = blocked.has(cellKey({ row, col }));
      const wrong: boolean = expectedEmpty
        ? value !== EMPTY_CELL
        : value < 1 || value > domainMax;
      if (wrong) {
        return "solution_shape";
      }
    }
  }
  return null;
}

export interface CageCells {
  readonly cells: readonly Cell[];
}

/**
 * A cage covers exactly its cells: inside the board, claimed once, and
 * together covering every fillable cell. A board whose cages leave a gap is a
 * board a player cannot finish, offline, with no way to report it.
 */
export function checkCageCoverage(
  board: Board,
  cages: readonly CageCells[],
): PuzzleRejectionTag | null {
  const claimed = new Set<string>();
  for (const cage of cages) {
    for (const cell of cage.cells) {
      if (!isInsideBoard(cell, board.size)) {
        return "cage_cell_outside_board";
      }
      const key: string = cellKey(cell);
      if (claimed.has(key)) {
        return "cage_cells_overlap";
      }
      claimed.add(key);
    }
  }
  const fillable: readonly Cell[] = fillableCells(board);
  const covered: boolean = fillable.every((cell) => claimed.has(cellKey(cell)));
  return covered && claimed.size === fillable.length ? null : "cage_coverage_incomplete";
}

/**
 * The smallest and largest sums a cage of this size can hold, given the digits
 * the board allows and no digit repeated inside the cage.
 */
export function checkSumReachable(
  cellCount: number,
  target: number,
  domain: readonly number[],
): PuzzleRejectionTag | null {
  const ascending: readonly number[] = [...domain].sort((left, right) => left - right);
  const total = (values: readonly number[]): number =>
    values.reduce((sum, value) => sum + value, 0);
  const smallest: number = total(ascending.slice(0, cellCount));
  const largest: number = total(ascending.slice(-cellCount));
  return target >= smallest && target <= largest ? null : "unreachable_target";
}
