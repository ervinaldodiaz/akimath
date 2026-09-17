import { MISCONCEPTION_COPY } from "./misconception-copy.js";

/**
 * The shape a diagnosis takes, spelled here rather than imported.
 *
 * It is structurally `@akimath/contract`'s `DiagnosisCopySchema`, and it is not
 * that import because this module is now reachable from `index.ts` —
 * `test/import_boundary.test.ts` holds the public surface to importing no
 * package at all, which is what "zero runtime dependencies" means when the
 * consumer is a server that ships. Structural typing makes the two
 * interchangeable at every call site; `parseMisconceptions` is what holds the
 * *values* to the frozen schema's rules.
 */
export interface MisconceptionCopy {
  readonly misconception: string;
  /** Mutable element type, matching the frozen schema's, so the two are
   * interchangeable without a cast at every boundary. Nothing mutates it. */
  readonly steps: string[];
  readonly explain: string;
}

/**
 * The Spanish a wrong answer is met with.
 *
 * **PURE** — decoded JSON in, a lookup out. Reading the file is the CLI's.
 *
 * **Copy lives in data, not in TypeScript.** It is prose about a specific
 * mistake, written and rewritten by whoever is best at writing it. In source,
 * every comma is a code review and the eventual translation pass becomes a
 * search through modules. The frozen `DiagnosisCopySchema` already requires
 * `misconception` to be a snake_case identifier, so the format anticipated a
 * keyed file.
 *
 * The key **is** the misconception, so the file does not repeat it inside each
 * entry — a shape that lets the two disagree.
 *
 * Identifiers are English and the copy is es-MX, which is the repository's rule
 * everywhere: only what a player reads is Spanish.
 */

/**
 * Words the copy may never contain.
 *
 * The same list `verdict_screen_test.dart` holds the verdict screens to, and
 * matched the same way — as substrings, which is why "normal" and "errores" are
 * also out. `req-diagnosis-copy` is about the product, not about one screen: a
 * diagnosis that opens by telling a learner they were wrong has spent its one
 * chance to be read.
 */
export const FORBIDDEN_WORDS: readonly string[] = [
  "incorrecto",
  "error",
  "fallaste",
  "mal",
];

const MISCONCEPTION_ID = /^[a-z][a-z0-9_]*$/u;

/** Every forbidden word found in a run of copy, for a caller that reports. */
export function scoldings(strings: Iterable<string>): readonly string[] {
  const found: string[] = [];
  for (const text of strings) {
    const lower = text.toLowerCase();
    for (const word of FORBIDDEN_WORDS) {
      if (lower.includes(word)) {
        found.push(`"${word}" in ${JSON.stringify(text)}`);
      }
    }
  }
  return found;
}

/** Every string of copy in a lookup, so a sweep can count what it checked. */
export function copyStrings(
  lookup: ReadonlyMap<string, MisconceptionCopy>,
): readonly string[] {
  return [...lookup.values()].flatMap((copy) => [copy.explain, ...copy.steps]);
}

/**
 * Decoded JSON held to the frozen schema's rules, keyed by misconception.
 *
 * **The scolding sweep runs at parse time**, so copy that names the failure
 * cannot reach a pack even where the caller forgets to look for it — the check
 * is not something a call site can be trusted to remember.
 */
export function parseMisconceptions(
  value: unknown,
): ReadonlyMap<string, MisconceptionCopy> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("misconceptions: must be an object keyed by identifier");
  }

  const lookup = new Map<string, MisconceptionCopy>();
  for (const [id, raw] of Object.entries(value as Record<string, unknown>)) {
    if (!MISCONCEPTION_ID.test(id)) {
      throw new TypeError(`misconceptions: "${id}" is not a snake_case identifier`);
    }
    const entry = raw as { steps?: unknown; explain?: unknown };
    const steps = entry.steps;
    if (
      !Array.isArray(steps) ||
      steps.length < 1 ||
      steps.length > 4 ||
      steps.some((s) => typeof s !== "string" || s.trim().length === 0)
    ) {
      throw new TypeError(`misconceptions: "${id}" needs one to four non-empty steps`);
    }
    if (typeof entry.explain !== "string" || entry.explain.trim().length === 0) {
      throw new TypeError(`misconceptions: "${id}" needs a non-empty explain`);
    }
    lookup.set(id, {
      misconception: id,
      steps: steps as string[],
      explain: entry.explain,
    });
  }

  if (lookup.size === 0) {
    throw new TypeError("misconceptions: the file declares none");
  }

  const offences = scoldings(copyStrings(lookup));
  if (offences.length > 0) {
    throw new TypeError(`misconceptions: the copy names the failure — ${offences.join("; ")}`);
  }

  return lookup;
}

/**
 * The copy, parsed on first use and shared after.
 *
 * A call rather than the map itself, for the reason `coreRegistry()` is one:
 * every export from this package is a function, and a `Map` carries methods.
 *
 * **Parsed lazily, not at module load.** A module-scope `parseMisconceptions(...)`
 * turns a bad edit into an *import* failure, and an import failure is not a
 * test failure: every file that imports this one dies before its assertions
 * run. Stryker reported six mutants as surviving for exactly that reason while
 * a hand falsification of the same line went red — the tests were fine and
 * could not run. Deferring it to the first call makes a bad edit fail where it
 * can be seen.
 */
let parsed: ReadonlyMap<string, MisconceptionCopy> | undefined;

export function misconceptionCopy(): ReadonlyMap<string, MisconceptionCopy> {
  parsed ??= parseMisconceptions(MISCONCEPTION_COPY);
  return parsed;
}

/**
 * What a wrong answer matching no predicted distractor gets told.
 *
 * Named here rather than in the build script, because the server issues packs
 * now and needs the same one. A skill with items and no fallback is a pack the
 * frozen validator refuses (`missing_skill_fallback`), so this is not optional
 * decoration.
 */
export const FALLBACK_MISCONCEPTION = "no_specific_diagnosis";

/** The fallback's copy, resolved at load so a missing key cannot reach a request. */
export function fallbackDiagnosis(): MisconceptionCopy {
  const copy = misconceptionCopy().get(FALLBACK_MISCONCEPTION);
  if (copy === undefined) {
    throw new TypeError(
      `the copy declares no "${FALLBACK_MISCONCEPTION}", so a wrong answer ` +
        "matching no distractor would have nothing to say",
    );
  }
  return copy;
}
