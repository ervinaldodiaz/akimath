import { mix64 } from "../prng/splitmix64.js";

import { cagePartition, type CageCells, type GridCell } from "./cages.js";
import { drawsFrom, shuffledIndices, type Draw } from "./draw.js";
import { latinSquare } from "./latin.js";

export type CagedKind = "kenken" | "killer";

export interface KenKenCage {
  readonly cells: CageCells;
  readonly operation: "+" | "-" | "×" | "÷";
  readonly target: number;
}

export interface KillerCage {
  readonly cells: CageCells;
  readonly target: number;
}

export interface CagedCandidate {
  readonly kind: CagedKind;
  readonly payload: Record<string, unknown>;
}

/**
 * How many cells a board prints, as a fraction of its cells.
 *
 * **Givens are what make a small KenKen uniquely solvable often enough to be
 * worth generating.** With none, most candidates at 4×4 and up admit more than
 * one solution and the contract refuses them; the generator stays correct and
 * produces almost nothing. Two printed cells cost a player very little and
 * raise the hit rate by an order of magnitude.
 */
const GIVEN_CELLS = 2;

/**
 * A candidate board of one caged kind.
 *
 * **PURE, and it judges nothing.** It builds a Latin square, partitions it and
 * labels the cages; whether the result is a puzzle is `parsePuzzle`'s to say
 * (design D1). There is no solver here, and there must not be: a second
 * implementation of "uniquely solvable" is free to disagree with the one that
 * ships, and the disagreement surfaces as a board a player cannot finish,
 * offline, with no way to report it.
 *
 * **Three decisions, three streams.** The square, the partition and the
 * labelling all draw from the same seed, and reading them off the same stream
 * would make each choice a function of the ones before it in a way nothing
 * states. `mix64` is the kernel's own mixing step, so a derived seed is as good
 * as an independent one and costs one multiply.
 *
 * Returns null when the square and partition cannot be labelled at all — a
 * Killer cage holding a repeated digit, which the contract forbids and this
 * cannot repair without becoming that second implementation. A Latin square
 * happily puts the same digit in two cells of one cage, so that is a real
 * outcome rather than a defensive branch.
 */
export function cagedCandidate(
  kind: CagedKind,
  seed: bigint,
  size: number,
): CagedCandidate | null {
  const partitionSeed = mix64(seed);
  const labelSeed = mix64(partitionSeed);

  const solution = latinSquare(seed, size);
  const cages = cagePartition(partitionSeed, size);
  const draw = drawsFrom(labelSeed);

  const valueAt = (cell: GridCell): number => solution[cell.row]![cell.col]!;

  const labelled: (KenKenCage | KillerCage)[] = [];
  for (const cage of cages) {
    const values = cage.map(valueAt);
    if (kind === "killer") {
      const digitsAreDistinct = new Set(values).size === values.length;
      if (!digitsAreDistinct) {
        return null;
      }
      labelled.push({ cells: cage, target: values.reduce((a, b) => a + b, 0) });
      continue;
    }
    labelled.push(kenKenCage(cage, values, draw));
  }

  return {
    kind,
    payload: {
      board: {
        size,
        blocked: [],
        given: givenCells(cages, draw),
        solution: solution.map((row) => [...row]),
      },
      cages: labelled,
    },
  };
}

/**
 * One cage's operation and result, drawn from the operations its values admit.
 *
 * A pair may support all four; a longer cage supports `+` and `×` only,
 * because a difference and a quotient are defined for two numbers — a rule the
 * contract states and this respects rather than restates.
 *
 * **A pair's difference is never zero, and there is no guard against it.** A
 * two-cell cage is a cell and an orthogonal neighbour, so the pair shares a row
 * or a column — and a Latin square never repeats a digit along either. A guard
 * here could not fire, and an unreachable guard is a claim about the code that
 * nothing checks.
 */
function kenKenCage(
  cells: CageCells,
  values: readonly number[],
  draw: Draw,
): KenKenCage {
  const sum = values.reduce((a, b) => a + b, 0);
  if (values.length === 1) {
    return { cells, operation: "+", target: sum };
  }

  const product = values.reduce((a, b) => a * b, 1);
  const options: KenKenCage[] = [
    { cells, operation: "+", target: sum },
    { cells, operation: "×", target: product },
  ];

  if (values.length === 2) {
    const [a, b] = [Math.max(values[0]!, values[1]!), Math.min(values[0]!, values[1]!)];
    options.push({ cells, operation: "-", target: a - b });
    if (a % b === 0) {
      options.push({ cells, operation: "÷", target: a / b });
    }
  }

  return options[draw(options.length - 1)]!;
}

/**
 * The cells the board prints, one from each of `GIVEN_CELLS` different cages.
 *
 * **Different cages, by construction rather than by retry.** Two givens inside
 * one cage pin the cage rather than the board, which is most of the reason an
 * authored magic square was once refused as `solution_not_unique`. Shuffling
 * the cage indices and taking a prefix makes that structural — a rejection
 * loop would have needed a bound that could never fire.
 *
 * Every chosen cell belongs to a cage of this board, so no bounds filter
 * follows: one would be unreachable, and an unreachable guard is a claim about
 * the code that nothing checks.
 *
 * The result is sorted, so the emitted payload's shape does not turn on the
 * order the draws happened to come out in — the pack is byte-diffed, and a
 * stable order is what makes that diff readable.
 */
function givenCells(cages: readonly CageCells[], draw: Draw): GridCell[] {
  const wanted = Math.min(GIVEN_CELLS, cages.length);

  return shuffledIndices(cages.length, draw)
    .slice(0, wanted)
    .map((at) => {
      const cage = cages[at]!;
      return cage[draw(cage.length - 1)]!;
    })
    .sort((a, b) => a.row - b.row || a.col - b.col);
}
