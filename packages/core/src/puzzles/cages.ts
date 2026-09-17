import { drawsFrom, type Draw } from "./draw.js";

export interface GridCell {
  readonly row: number;
  readonly col: number;
}

export type CageCells = readonly GridCell[];

/**
 * The largest cage this generator proposes.
 *
 * **A solvability heuristic, not a rule about cages** (design D4). A larger
 * cage constrains less, so the contract's search finds more than one solution
 * and refuses the board — the generator would still be correct, just slower and
 * emptier. `KenKenPayloadSchema` permits bigger cages; this simply does not
 * offer them.
 */
export const MAX_CAGE_CELLS = 4;

const NEIGHBOURS: readonly (readonly [number, number])[] = [
  [0, 1],
  [0, -1],
  [1, 0],
  [-1, 0],
];

/**
 * A seeded partition of a `size`×`size` board into connected cages.
 *
 * **PURE.** Grown rather than cut: a cage starts at an unassigned cell and
 * annexes an unassigned orthogonal neighbour at each step, so it is connected
 * by construction rather than by a check afterwards.
 *
 * **Cage start points are visited in reading order, not shuffled.** The growth
 * is what varies; walking them in a random order as well would spend draws for
 * no extra variety, because every unassigned cell starts a cage either way.
 *
 * A cage's ceiling costs one less draw than `MAX_CAGE_CELLS` suggests: a cage
 * of one is common enough in a real KenKen to be worth offering. It is a
 * ceiling and not a size, because growth may not reach it when the
 * neighbourhood is already full.
 */
export function cagePartition(seed: bigint, size: number): readonly CageCells[] {
  if (size < 3) {
    throw new RangeError(`a board below 3 has no partition worth making: ${size}`);
  }

  const draw = drawsFrom(seed);

  const taken: boolean[][] = Array.from({ length: size }, () =>
    Array.from({ length: size }, () => false),
  );
  const cages: GridCell[][] = [];

  for (let row = 0; row < size; row += 1) {
    for (let col = 0; col < size; col += 1) {
      if (taken[row]![col]!) {
        continue;
      }
      const cageCeiling = 1 + draw(MAX_CAGE_CELLS - 1);
      cages.push(grow({ row, col }, cageCeiling, taken, size, draw));
    }
  }

  return cages;
}

function grow(
  start: GridCell,
  ceiling: number,
  taken: boolean[][],
  size: number,
  draw: Draw,
): GridCell[] {
  const cage: GridCell[] = [start];
  taken[start.row]![start.col] = true;

  while (cage.length < ceiling) {
    const options: GridCell[] = [];
    for (const cell of cage) {
      for (const [dr, dc] of NEIGHBOURS) {
        const row = cell.row + dr;
        const col = cell.col + dc;
        if (row < 0 || col < 0 || row >= size || col >= size || taken[row]![col]!) {
          continue;
        }
        options.push({ row, col });
      }
    }
    if (options.length === 0) {
      break;
    }
    const chosen = options[draw(options.length - 1)]!;
    taken[chosen.row]![chosen.col] = true;
    cage.push(chosen);
  }

  return cage;
}
