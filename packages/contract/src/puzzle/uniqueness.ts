import { boardLines, cellKey, EMPTY_CELL, fillableCells, type Board, type Cell } from "./board.js";
import type { PuzzleRejectionTag } from "./rejection.js";

/**
 * The solver that decides whether a board is playable. Trusting the author and
 * checking only cage coverage ships a puzzle a player cannot finish, offline,
 * with no way to report it — so the search is exhaustive (design.md D10).
 *
 * The 6×6 cap of plan §5.3 D15 bounds the board, not the search: a magic
 * square draws its digits from 1..size², and a kakuro run from 1..9, so the
 * tree a weakly constrained board opens is measured in minutes. `SEARCH_NODE_BUDGET`
 * is what bounds it, and a board that outruns the budget is rejected by name.
 *
 * Every kind expresses itself as regions over the same board, so one search
 * serves KenKen, Killer, Kakuro and the magic square.
 */
export const CAGE_OPERATIONS = ["+", "-", "×", "÷"] as const;

export type CageOperation = (typeof CAGE_OPERATIONS)[number];

export type RegionRule =
  | { readonly kind: "distinct" }
  | { readonly kind: "sum"; readonly target: number; readonly distinct: boolean }
  | { readonly kind: "arithmetic"; readonly operation: CageOperation; readonly target: number };

export interface Region {
  readonly cells: readonly Cell[];
  readonly rule: RegionRule;
}

export interface ConstraintProblem {
  readonly board: Board;
  readonly domain: readonly number[];
  readonly regions: readonly Region[];
}

/** Rows and columns hold each digit once — the Latin rule KenKen and Killer share. */
export function latinRegions(board: Board): readonly Region[] {
  return boardLines(board.size).flatMap((line): readonly Region[] => [
    { cells: line.row, rule: { kind: "distinct" } },
    { cells: line.column, rule: { kind: "distinct" } },
  ]);
}

/**
 * A printed cell pins itself: its value comes from the declared solution, so
 * the board states a given once rather than twice.
 */
export function givenRegions(board: Board): readonly Region[] {
  return board.given.map((cell) => ({
    cells: [cell],
    rule: {
      kind: "sum" as const,
      target: board.solution[cell.row]?.[cell.col] ?? EMPTY_CELL,
      distinct: false,
    },
  }));
}

function hasDuplicate(values: readonly number[]): boolean {
  return new Set(values).size !== values.length;
}

function product(values: readonly number[]): number {
  return values.reduce((carried, value) => carried * value, 1);
}

function total(values: readonly number[]): number {
  return values.reduce((carried, value) => carried + value, 0);
}

function arithmeticHolds(rule: RegionRule & { kind: "arithmetic" }, values: readonly number[]): boolean {
  const [first, second] = values;
  switch (rule.operation) {
    case "+":
      return total(values) === rule.target;
    case "×":
      return product(values) === rule.target;
    case "-":
      return (
        values.length === 2 &&
        first !== undefined &&
        second !== undefined &&
        Math.abs(first - second) === rule.target
      );
    case "÷":
      return (
        values.length === 2 &&
        first !== undefined &&
        second !== undefined &&
        Math.max(first, second) === rule.target * Math.min(first, second)
      );
  }
}

/** Every cell of the region is filled: does the rule hold on what is there? */
function ruleSatisfied(rule: RegionRule, values: readonly number[]): boolean {
  switch (rule.kind) {
    case "distinct":
      return !hasDuplicate(values);
    case "sum":
      return !(rule.distinct && hasDuplicate(values)) && total(values) === rule.target;
    case "arithmetic":
      return arithmeticHolds(rule, values);
  }
}

/**
 * The region still has empty cells: can no completion of it satisfy the rule,
 * so the branch is already dead? Every domain digit is at least 1, which is
 * what makes a partial sum that has reached its target unrecoverable. An
 * arithmetic cage says nothing until it is full, so it prunes nothing.
 */
function rulePrunable(rule: RegionRule, values: readonly number[]): boolean {
  switch (rule.kind) {
    case "distinct":
      return hasDuplicate(values);
    case "sum":
      return (rule.distinct && hasDuplicate(values)) || total(values) >= rule.target;
    case "arithmetic":
      return false;
  }
}

interface RegionView {
  readonly keys: readonly string[];
  readonly rule: RegionRule;
}

function viewsTouching(regions: readonly Region[]): ReadonlyMap<string, readonly RegionView[]> {
  const byCell = new Map<string, RegionView[]>();
  for (const region of regions) {
    const view: RegionView = { keys: region.cells.map(cellKey), rule: region.rule };
    for (const key of view.keys) {
      const existing: RegionView[] = byCell.get(key) ?? [];
      existing.push(view);
      byCell.set(key, existing);
    }
  }
  return byCell;
}

function stillConsistent(
  view: RegionView,
  assignment: ReadonlyMap<string, number>,
): boolean {
  const values: number[] = [];
  for (const key of view.keys) {
    const value: number | undefined = assignment.get(key);
    if (value !== undefined) {
      values.push(value);
    }
  }
  return values.length === view.keys.length
    ? ruleSatisfied(view.rule, values)
    : !rulePrunable(view.rule, values);
}

export interface SearchBounds {
  /** Stop once this many solutions are in hand; two settles uniqueness. */
  readonly solutionLimit: number;
  /** Value trials the search may spend before it declares the board unaffordable. */
  readonly nodeBudget: number;
}

/**
 * Either the search finished inside its bounds, or it ran out of budget and
 * decided nothing. `nodes` is what it spent either way, which is the only
 * observable that tells stronger pruning from weaker pruning.
 */
export type SearchOutcome =
  | { readonly kind: "counted"; readonly solutions: number; readonly nodes: number }
  | { readonly kind: "budgetExhausted"; readonly nodes: number };

/**
 * Measured, not guessed: the costliest 6×6 board this package accepts is the
 * kakuro fixture at 34 308 value trials, so 500 000 carries roughly fifteen
 * times the worst legitimate cost and still returns in well under a second.
 * A board that outruns it is content no author can wait on, and it is named
 * rather than left to run (design.md D10).
 */
export const SEARCH_NODE_BUDGET = 500_000;

function search(
  problem: ConstraintProblem,
  bounds: SearchBounds,
  found: (assignment: ReadonlyMap<string, number>) => void,
): SearchOutcome {
  const cells: readonly Cell[] = fillableCells(problem.board);
  const touching: ReadonlyMap<string, readonly RegionView[]> = viewsTouching(problem.regions);
  const assignment = new Map<string, number>();
  let solutions = 0;
  let nodes = 0;
  let exhausted = false;

  /**
   * Both counters only ever grow, so these two guards also unwind the
   * recursion: whichever frame trips one, every frame above it trips the same
   * one on its next value and returns.
   */
  const place = (index: number): void => {
    const cell: Cell | undefined = cells[index];
    if (cell === undefined) {
      solutions += 1;
      found(assignment);
      return;
    }
    const key: string = cellKey(cell);
    for (const value of problem.domain) {
      if (solutions >= bounds.solutionLimit) {
        return;
      }
      if (nodes >= bounds.nodeBudget) {
        exhausted = true;
        return;
      }
      nodes += 1;
      assignment.set(key, value);
      const consistent: boolean = (touching.get(key) ?? []).every((view) =>
        stillConsistent(view, assignment),
      );
      if (consistent) {
        place(index + 1);
      }
      assignment.delete(key);
    }
  };

  place(0);
  return exhausted ? { kind: "budgetExhausted", nodes } : { kind: "counted", solutions, nodes };
}

export function searchSolutions(problem: ConstraintProblem, bounds: SearchBounds): SearchOutcome {
  return search(problem, bounds, () => undefined);
}

function matchesDeclared(
  board: Board,
  assignment: ReadonlyMap<string, number>,
): boolean {
  return fillableCells(board).every(
    (cell) => assignment.get(cellKey(cell)) === board.solution[cell.row]?.[cell.col],
  );
}

/**
 * Exactly one assignment satisfies the constraints, and it is the one the pack
 * declares. Anything else is a board the client would grade wrongly.
 *
 * The budget only bites while the verdict is still open: `search` checks the
 * solution limit before the node budget, so a second solution already in hand
 * is never downgraded to "unknown".
 */
export function checkUniqueSolution(problem: ConstraintProblem): PuzzleRejectionTag | null {
  let declaredWasFound = false;
  const outcome: SearchOutcome = search(
    problem,
    { solutionLimit: 2, nodeBudget: SEARCH_NODE_BUDGET },
    (assignment) => {
      declaredWasFound = declaredWasFound || matchesDeclared(problem.board, assignment);
    },
  );
  if (outcome.kind === "budgetExhausted") {
    return "search_budget_exhausted";
  }
  if (outcome.solutions > 1) {
    return "solution_not_unique";
  }
  return outcome.solutions === 1 && declaredWasFound ? null : "solution_mismatch";
}
