import { mkdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  generateCagedBatch,
  generateKakuroBatch,
  generateMagicSquareBatch,
  generateWordSearchBatch,
  type Batch,
  type PuzzleCopy,
} from "../puzzles/batch.js";
import { flag } from "./flags.js";
import type { CagedKind } from "../puzzles/caged.js";

/**
 * Writes a batch of caged boards.
 *
 * **The one adapter.** Everything it does with the contents is
 * `src/puzzles/`'s; this reads flags, hands them over, and writes the result.
 * It reads no clock and draws no randomness of its own — the seed comes from
 * the command line, so the same command produces the same file and a diff
 * means something.
 *
 * A board is not a pack. This writes envelopes for someone to paste into an
 * authored pack, deliberately: which boards ship is a content decision, and a
 * generator that appended to the pack directly would be making it.
 */
const CAGED_KINDS: readonly CagedKind[] = ["kenken", "killer"];

/** Every kind this generator can build. */
export type BuildableKind = CagedKind | "wordSearch" | "magicSquare" | "kakuro";

const KINDS: readonly BuildableKind[] = [
  ...CAGED_KINDS,
  "wordSearch",
  "magicSquare",
  "kakuro",
];

/**
 * The words a sopa de letras may hide.
 *
 * **Content, and it lives in the adapter** for the same reason the copy does:
 * `src/puzzles/` has no business holding a Spanish word list. Unaccented and
 * uppercase, because the contract's cell is `[A-ZÑ]` — a `Ú` is not a letter
 * this format can print, and a grid that quietly dropped the accent would be
 * teaching the wrong spelling.
 */
const VOCABULARY: readonly string[] = [
  "SUMA",
  "RESTA",
  "CERO",
  "DOBLE",
  "MITAD",
  "NUMERO",
  "DECENA",
  "UNIDAD",
  "TRIPLE",
  "PARES",
  "IMPAR",
  "TOTAL",
  "MEDIDA",
  "CUENTA",
];

/** The es-MX tutorial each kind carries, shown once before its first board. */
const TUTORIAL: Readonly<Record<BuildableKind, readonly string[]>> = Object.freeze({
  kenken: [
    "Cada fila y cada columna llevan cada número una vez.",
    "La esquina de la jaula dice el resultado y con qué operación.",
  ],
  killer: [
    "Cada fila y cada columna llevan cada número una vez.",
    "La esquina de la jaula dice a cuánto suman sus celdas.",
  ],
  wordSearch: [
    "Arrastra el dedo de la primera letra a la última.",
    "Una palabra puede ir en cualquiera de las ocho direcciones.",
  ],
  magicSquare: [
    "Cada fila y cada columna llegan al número de su ficha.",
    "Ningún número se repite en todo el cuadro.",
  ],
  kakuro: [
    "Cada tramo suma el número de su pista.",
    "Dentro de un tramo no se repite ningún dígito.",
  ],
});

/**
 * How many lines a reference sheet has, in every format.
 *
 * **Objective, then vocabulary, then constraints** — the design annotates
 * `3.3 Hoja de referencia` as *"consulta, no clase"*, and a fixed three keeps
 * the card one shape rather than one per kind. The frozen schema admits one to
 * six; three is a product decision, so it is stated here and asserted in
 * `test/reference-sheet.test.ts` rather than left implicit in five literals.
 */
export const REFERENCE_SHEET_LINES = 3;

/**
 * The sheet a player opens mid-board, for a board of this kind at this size.
 *
 * **Size is a parameter because the objective cannot be stated without it.**
 * The sheets these boards used to carry said *"del 1 al tamaño del cuadro"*,
 * which asks a player mid-board to work out the answer to the question they
 * opened the sheet to ask. A 5×5 KenKen now says *del 1 al 5* and a 3×3 magic
 * square says *del 1 al 9*, because a magic square holds one of every number up
 * to its cell count and a caged board holds one of every number up to its side.
 *
 * The operators are the characters `puzzle_board_view.dart` prints in a cage's
 * corner — an ASCII hyphen, not U+2212 — because a reference sheet that spells
 * a mark differently from the board is not a reference.
 */
export function referenceSheetFor(
  kind: BuildableKind,
  size: number,
): readonly string[] {
  switch (kind) {
    case "kenken":
      return [
        `Llena todas las casillas con números del 1 al ${size}.`,
        "Las jaulas son los grupos de casillas con borde punteado: en su esquina traen el resultado y el signo (+ suma, - resta, × multiplica, ÷ divide).",
        "Las casillas de cada jaula dan ese resultado en el orden que sea, y ningún número se repite en su fila ni en su columna.",
      ];
    case "killer":
      return [
        `Llena todas las casillas con números del 1 al ${size}.`,
        "Las jaulas son los grupos de casillas con borde punteado: en su esquina traen a cuánto suman, sin signo porque siempre se suma.",
        "Cada jaula llega a esa suma sin repetir ningún número, y tampoco se repite ninguno en su fila ni en su columna.",
      ];
    case "magicSquare":
      return [
        `Llena todas las casillas con los números del 1 al ${size * size}, uno en cada una.`,
        "Las fichas de la orilla son los objetivos: dicen a cuánto tiene que llegar cada fila y cada columna.",
        "Cada fila y cada columna suman justo su objetivo, y ningún número se repite en el cuadro.",
      ];
    case "kakuro":
      return [
        "Llena las casillas blancas con dígitos del 1 al 9.",
        "El tramo es una hilera de casillas blancas seguidas; la casilla oscura donde empieza dice a cuánto suma.",
        "Cada tramo suma justo esa pista, y dentro de un tramo no se repite ningún dígito.",
      ];
    case "wordSearch":
      return [
        "Encuentra en la cuadrícula todas las palabras de la lista.",
        "Arrastra el dedo desde la primera letra hasta la última y la palabra queda marcada.",
        "Las palabras van en línea recta, en cualquiera de las ocho direcciones, y nunca dan vuelta.",
      ];
  }
}

/** The es-MX copy a board of this kind and size carries. */
function copyFor(kind: BuildableKind, size: number): PuzzleCopy {
  return {
    tutorialSteps: TUTORIAL[kind],
    referenceSheet: referenceSheetFor(kind, size),
  };
}

function requireKind(raw: string): BuildableKind {
  const found = KINDS.find((kind) => kind === raw);
  if (found === undefined) {
    throw new TypeError(`--kind must be one of ${KINDS.join(", ")}, not ${raw}`);
  }
  return found;
}

function requirePositive(name: string, raw: string): number {
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new TypeError(`--${name} must be a positive whole number, not ${raw}`);
  }
  return value;
}

function switchKind(
  kind: BuildableKind,
  size: number,
  count: number,
  firstSeed: bigint,
): Batch {
  const copy = copyFor(kind, size);
  switch (kind) {
    case "wordSearch":
      return generateWordSearchBatch(
        { size, count, firstSeed, vocabulary: VOCABULARY },
        copy,
      );
    case "magicSquare":
      return generateMagicSquareBatch({ size, count, firstSeed }, copy);
    case "kakuro":
      return generateKakuroBatch({ size, count, firstSeed }, copy);
    default:
      return generateCagedBatch({ kind, size, count, firstSeed }, copy);
  }
}

/**
 * Reads the flags, generates the batch and writes the boards.
 *
 * **The batch is written through a temporary file.** `> out` truncates before
 * the producer has run, so a refusal used to leave the committed artifact
 * destroyed. A failed write unlinks the temporary and rethrows, and if that
 * unlink also fails there is nothing to clean up: the original is untouched
 * either way.
 */
function main(): void {
  const kind = requireKind(flag("kind", "kenken"));
  const size = requirePositive("size", flag("size", "4"));
  const count = requirePositive("count", flag("count", "3"));
  const firstSeed = BigInt(flag("seed", "1"));
  const out = path.resolve(flag("out", `puzzles-${kind}-${size}.json`));

  const batch: Batch = switchKind(kind, size, count, firstSeed);

  mkdirSync(path.dirname(out), { recursive: true });
  const temporary = `${out}.tmp`;
  try {
    writeFileSync(temporary, `${JSON.stringify(batch.boards, null, 2)}\n`, "utf8");
    renameSync(temporary, out);
  } catch (cause) {
    try {
      unlinkSync(temporary);
    } catch {}
    throw cause;
  }

  const refused = Object.entries(batch.report.refused)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([tag, n]) => `${tag} ${n}`)
    .join(", ");
  // eslint-disable-next-line no-console
  console.log(
    `puzzles: ${batch.report.accepted}/${count} ${kind} ${size}×${size} ` +
      `in ${batch.report.attempts} attempts → ${out}\n` +
      `         refused: ${refused === "" ? "nothing" : refused}` +
      (batch.report.exhausted ? "\n         BUDGET EXHAUSTED — fewer boards than asked for" : ""),
  );
}

/**
 * Whether this module was run, rather than imported.
 *
 * **Without it, reading the copy generates a batch.** `referenceSheetFor` is
 * the one definition of words that also ship inside
 * `app/assets/packs/starter.json`, and the test that holds those two together
 * has to import this file — which, at module scope, built three 4×4 KenKens and
 * wrote `puzzles-kenken-4.json` into the package root. Measured, not guessed:
 * the file was there after the first run of that test.
 */
const runFromCommandLine =
  process.argv[1] !== undefined &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (runFromCommandLine) {
  try {
    main();
  } catch (cause) {
    // eslint-disable-next-line no-console
    console.error(`puzzles: ${cause instanceof Error ? cause.message : String(cause)}`);
    process.exitCode = 1;
  }
}
