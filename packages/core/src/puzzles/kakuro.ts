import { drawsFrom, shuffledIndices, type Draw } from "./draw.js";

/** The digits a Kakuro cell may hold, whatever the board's size. */
const HIGHEST_DIGIT = 9;

/**
 * How much of the board is printed, by size — measured, not chosen.
 *
 * Accepted candidates over forty seeds per cell:
 *
 * | | 0.35 | 0.5 | 0.6 |
 * |---|---|---|---|
 * | 4×4 | 6/40 | **19/40** | 22/40 |
 * | 5×5 | 2/40 | **12/40** | 13/40 |
 * | 6×6 | 3/40 | 4/40 | 7/40 |
 *
 * The jump is between 0.35 and 0.5; 0.6 buys almost nothing on top and prints
 * three fifths of the answer, so 0.5 is where the returns stop. A 3×3 needs
 * none of it — at 0.35 it already accepts 8 of 40, and the same fraction that
 * rescues a 5×5 would hand a 3×3 over.
 */
function printedFraction(size: number): number {
  return size <= 3 ? 0.35 : 0.5;
}

export interface KakuroCandidate {
  readonly kind: "kakuro";
  readonly payload: Record<string, unknown>;
}

interface Cell {
  readonly row: number;
  readonly col: number;
}

/**
 * A candidate Kakuro, or the name of the reason there is none.
 *
 * **PURE, and it judges nothing.** It blocks some cells, fills the rest so that
 * every run holds distinct digits, and reads each run's clue off the fill it
 * just made — so the *arithmetic* is true by construction. Whether the board
 * has one solution is `parsePuzzle`'s to decide, the same split the other three
 * generators use.
 *
 * Kakuro differs from them in one structural way: **runs cross**, so a cell
 * belongs to a horizontal run and a vertical one and coverage is "in at least
 * one run" rather than a partition. A cell whose runs are both length one is in
 * none, which the contract refuses as `cage_coverage_incomplete` — so this
 * refuses it first, by name, rather than proposing a board it knows is wrong.
 * Such a cell can never be deduced, and the refusal is named
 * `a_cell_belongs_to_no_run` so that a collapse in hit rate reads as *this* and
 * not as a solver rejection.
 */
export function kakuroCandidate(
  seed: bigint,
  size: number,
): KakuroCandidate | string {
  if (size < 3 || size > 6) {
    return "size_outside_the_format";
  }

  const draw: Draw = drawsFrom(seed);
  const blocked = blockedCells(seed, size, draw);
  const isBlocked = (row: number, col: number): boolean =>
    blocked.some((cell) => cell.row === row && cell.col === col);

  const runs = maximalRuns(size, isBlocked);
  if (!everyCellIsInARun(size, isBlocked, runs)) {
    return "a_cell_belongs_to_no_run";
  }

  const solution = fillBoard(size, isBlocked, runs, draw);
  if (solution === null) {
    return "no_fill_keeps_every_run_distinct";
  }

  const given = printedCells(size, isBlocked, draw, printedFraction(size));

  return {
    kind: "kakuro",
    payload: {
      board: {
        size,
        blocked: [...blocked].sort((a, b) => a.row - b.row || a.col - b.col),
        given,
        solution,
      },
      runs: runs.map((run) => ({
        cells: run,
        sum: run.reduce(
          (total, cell) => total + solution[cell.row]![cell.col]!,
          0,
        ),
      })),
    },
  };
}

/**
 * The black squares.
 *
 * Never the whole of a row or a column, and never so many that the board stops
 * being one — a third is what leaves runs long enough to be worth solving.
 */
function blockedCells(seed: bigint, size: number, draw: Draw): Cell[] {
  const cells = size * size;
  const wanted = Math.round(cells / 3);
  return shuffledIndices(cells, draw)
    .slice(0, wanted)
    .map((at) => ({ row: Math.floor(at / size), col: at % size }));
}

/** Every cell a player may fill, in reading order. */
function openCells(
  size: number,
  isBlocked: (row: number, col: number) => boolean,
): Cell[] {
  const open: Cell[] = [];
  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) {
      if (!isBlocked(row, col)) {
        open.push({ row, col });
      }
    }
  }
  return open;
}

/** Every horizontal and vertical run of two or more open cells. */
function maximalRuns(
  size: number,
  isBlocked: (row: number, col: number) => boolean,
): Cell[][] {
  const runs: Cell[][] = [];
  const collect = (line: Cell[]): void => {
    if (line.length >= 2) {
      runs.push([...line]);
    }
  };

  for (let row = 0; row < size; row += 1) {
    let line: Cell[] = [];
    for (let col = 0; col < size; col += 1) {
      if (isBlocked(row, col)) {
        collect(line);
        line = [];
      } else {
        line.push({ row, col });
      }
    }
    collect(line);
  }
  for (let col = 0; col < size; col += 1) {
    let line: Cell[] = [];
    for (let row = 0; row < size; row += 1) {
      if (isBlocked(row, col)) {
        collect(line);
        line = [];
      } else {
        line.push({ row, col });
      }
    }
    collect(line);
  }
  return runs;
}

function everyCellIsInARun(
  size: number,
  isBlocked: (row: number, col: number) => boolean,
  runs: readonly Cell[][],
): boolean {
  const covered = new Set<string>();
  for (const run of runs) {
    for (const cell of run) {
      covered.add(`${cell.row},${cell.col}`);
    }
  }
  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) {
      if (!isBlocked(row, col) && !covered.has(`${row},${col}`)) {
        return false;
      }
    }
  }
  return true;
}

/**
 * Digits for every open cell, distinct within each run.
 *
 * **Exported for the sake of its own failure.** With runs of at most six cells
 * and nine digits to choose from, a fill always exists — so the `null` it can
 * return is unreachable through `kakuroCandidate` and would rot unverified.
 * `drawBelow` was split out of `intBetween` for exactly this reason, and this
 * follows it: a test hands this a run of ten cells and sees the guard hold.
 *
 * Backtracking in reading order. The candidates are shuffled per cell so two
 * seeds do not produce the same board, and the recursion is bounded by the
 * board — at 6×6 that is at most 36 cells over 9 digits, which the contract's
 * own solver would find trivial and which is cheap enough to run per attempt.
 *
 * **A run longer than the digit ceiling is refused before the search, not
 * during it.** Such a run cannot hold distinct digits however it is filled, and
 * discovering that by backtracking costs `9!` dead ends — enough to time a test
 * out. Nine cells is the most a run can carry.
 */
export function fillBoard(
  size: number,
  isBlocked: (row: number, col: number) => boolean,
  runs: readonly Cell[][],
  draw: Draw,
): number[][] | null {
  if (runs.some((run) => run.length > HIGHEST_DIGIT)) {
    return null;
  }

  const grid: number[][] = Array.from({ length: size }, () =>
    Array.from({ length: size }, () => 0),
  );
  const runsOf = new Map<string, Cell[][]>();
  for (const run of runs) {
    for (const cell of run) {
      const key = `${cell.row},${cell.col}`;
      runsOf.set(key, [...(runsOf.get(key) ?? []), run]);
    }
  }

  const open = openCells(size, isBlocked);

  const orders = open.map(() =>
    shuffledIndices(HIGHEST_DIGIT, draw).map((at) => at + 1),
  );

  const fits = (cell: Cell, value: number): boolean =>
    (runsOf.get(`${cell.row},${cell.col}`) ?? []).every((run) =>
      run.every(
        (other) =>
          (other.row === cell.row && other.col === cell.col) ||
          grid[other.row]![other.col] !== value,
      ),
    );

  const place = (at: number): boolean => {
    if (at === open.length) {
      return true;
    }
    const cell = open[at]!;
    for (const value of orders[at]!) {
      if (!fits(cell, value)) {
        continue;
      }
      grid[cell.row]![cell.col] = value;
      if (place(at + 1)) {
        return true;
      }
      grid[cell.row]![cell.col] = 0;
    }
    return false;
  };

  return place(0) ? grid : null;
}

/** The cells the board prints. Blocked cells are never among them. */
function printedCells(
  size: number,
  isBlocked: (row: number, col: number) => boolean,
  draw: Draw,
  fraction: number,
): Cell[] {
  const open = openCells(size, isBlocked);
  const wanted = Math.max(1, Math.round(open.length * fraction));
  return shuffledIndices(open.length, draw)
    .slice(0, wanted)
    .map((at) => open[at]!)
    .sort((a, b) => a.row - b.row || a.col - b.col);
}
