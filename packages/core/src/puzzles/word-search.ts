import { drawsFrom, shuffledIndices, type Draw } from "./draw.js";

/** Every direction a word may run, in the order the contract lists them. */
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
 * The letters an unused cell may take.
 *
 * **`Ñ` is in, and accents are out.** The contract's cell is `[A-ZÑ]`, so a
 * filler outside that alphabet is a payload the validator refuses — and a
 * player reading a Spanish grid with no `Ñ` in it anywhere would notice.
 */
const FILLER = "ABCDEFGHIJKLMNÑOPQRSTUVWXYZ";

/** The most words the contract admits in one puzzle. */
const MAX_WORDS = 8;

export interface WordSearchCandidate {
  readonly kind: "wordSearch";
  readonly payload: {
    readonly grid: readonly (readonly string[])[];
    readonly words: readonly string[];
  };
}

/**
 * A candidate sopa de letras.
 *
 * **PURE, and it judges nothing** (the caged generator's design D1). It places
 * what it can and fills the rest; whether the result is a puzzle — in
 * particular whether the filler accidentally spelled a listed word a second
 * time — is `parsePuzzle`'s to say. `word_occurs_twice` is a rejection in the
 * contract, and detecting it here would be a second implementation of a rule
 * that already exists.
 *
 * Returns null when nothing can be placed at all: a vocabulary whose words are
 * all longer than the grid, or an empty one. That is not a puzzle to reject, it
 * is a request that cannot be met.
 *
 * **Words are tried in a shuffled order, and deliberately not longest-first.**
 * That is the obvious heuristic — a long word has the fewest places to go — and
 * it was written, then measured: over sixty seeds it placed 5.00 words against
 * 4.77 at 5×5, *6.13 against 6.20* at 6×6, and made no difference at all at
 * 8×8, where every word fits either way. A heuristic that cannot be told from
 * chance is a claim in a comment rather than a property of the code, so it is
 * gone.
 *
 * A word too long for the grid is dropped before the search rather than left to
 * fail placement: it saves the search, and it is the only case where "no" is
 * knowable without looking at the grid.
 *
 * The words come back in the order the caller gave, not the order they were
 * placed: the list a player reads is content, and "longest first" is this
 * function's business rather than theirs.
 *
 * The vocabulary is the caller's. Which words a player meets is content, and
 * the generator has no business holding a Spanish word list.
 */
export function wordSearchCandidate(
  seed: bigint,
  size: number,
  vocabulary: readonly string[],
): WordSearchCandidate | null {
  const draw = drawsFrom(seed);
  const grid: (string | null)[][] = Array.from({ length: size }, () =>
    Array.from({ length: size }, () => null),
  );

  const shuffledWordsThatFit = shuffledIndices(vocabulary.length, draw)
    .map((at) => vocabulary[at]!)
    .filter((word) => word.length <= size);

  const placed: string[] = [];
  for (const word of shuffledWordsThatFit) {
    if (placed.length === MAX_WORDS) {
      break;
    }
    if (place(grid, word, size, draw)) {
      placed.push(word);
    }
  }
  if (placed.length === 0) {
    return null;
  }

  return {
    kind: "wordSearch",
    payload: {
      grid: grid.map((row) =>
        row.map((cell) => cell ?? FILLER[draw(FILLER.length - 1)]!),
      ),
      words: vocabulary.filter((word) => placed.includes(word)),
    },
  };
}

/**
 * Writes `word` somewhere it fits, or reports that it does not.
 *
 * Every start and direction is tried, in a seeded order, and a cell already
 * holding the right letter counts as free — overlaps are what make a grid feel
 * woven rather than striped.
 */
function place(
  grid: (string | null)[][],
  word: string,
  size: number,
  draw: Draw,
): boolean {
  const cells = size * size;
  const starts = shuffledIndices(cells, draw);
  const directions = shuffledIndices(DIRECTIONS.length, draw);

  for (const start of starts) {
    const row = Math.floor(start / size);
    const col = start % size;
    for (const at of directions) {
      const [dr, dc] = DIRECTIONS[at]!;
      if (fits(grid, word, row, col, dr, dc, size)) {
        for (const [index, letter] of [...word].entries()) {
          grid[row + dr * index]![col + dc * index] = letter;
        }
        return true;
      }
    }
  }
  return false;
}

function fits(
  grid: readonly (readonly (string | null)[])[],
  word: string,
  row: number,
  col: number,
  dr: number,
  dc: number,
  size: number,
): boolean {
  return [...word].every((letter, index) => {
    const r = row + dr * index;
    const c = col + dc * index;
    if (r < 0 || c < 0 || r >= size || c >= size) {
      return false;
    }
    const held = grid[r]![c];
    return held === null || held === letter;
  });
}
