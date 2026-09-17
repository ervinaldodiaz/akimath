import { mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { resolve } from "../registry.js";
import { CORE_REGISTRY } from "../templates/index.js";
import { buildPack } from "../pack/build.js";
import { parseDeclaration, type Declaration } from "../pack/declaration.js";
import { fallbackDiagnosis, misconceptionCopy } from "../pack/misconceptions.js";
import { flag } from "./flags.js";

/**
 * Writes the committed pack.
 *
 * **The one adapter.** Everything it does with the contents is
 * `packages/core/src/pack/`'s; this reads files, hands them over, and writes
 * the result. It reads no clock — `issued_at` and `expires_at` come from the
 * declaration — so the same inputs produce the same bytes and the CI diff means
 * something.
 */

const here = (relative: string): string =>
  fileURLToPath(new URL(relative, import.meta.url));

/**
 * Paths, overridable from the command line.
 *
 * Defaults are what `npm run build:pack` uses. The overrides exist so the
 * refusal path can be exercised for real — a test that cannot point this at a
 * broken declaration can only assert that the happy path works, and "writes no
 * file when it fails" is precisely the behaviour worth proving.
 */
const DECLARATION = path.resolve(flag("declaration", here("../../content/pack.declaration.json")));
const OUT = path.resolve(flag("out", here("../../pack/starter.json")));

/**
 * Every skill the declaration's items are filed under.
 *
 * Puzzles belong to no skill, so only the item sources contribute one — and a
 * template source contributes its *template's*, which is the only place that
 * fact is written down now.
 */
function skillIdsOfItemSources(declaration: Declaration): Set<number> {
  return new Set(
    declaration.sources.flatMap((source) => {
      switch (source.kind) {
        case "puzzles":
          return [];
        case "authored":
          return [source.skillId];
        case "template":
          return [resolve(CORE_REGISTRY, source).skillId];
      }
    }),
  );
}

/**
 * The boards a pack carries, counted per kind rather than listed.
 *
 * A pack carrying four KenKens used to print "kenken" four times, which reads
 * as a bug in the report rather than as content.
 */
function describePuzzles(puzzleKinds: readonly string[]): string {
  if (puzzleKinds.length === 0) {
    return "no puzzles";
  }
  const perKind = new Map<string, number>();
  for (const kind of puzzleKinds) {
    perKind.set(kind, (perKind.get(kind) ?? 0) + 1);
  }
  return `${puzzleKinds.length} puzzles (${[...perKind.entries()]
    .map(([kind, n]) => `${kind} ${n}`)
    .join(", ")})`;
}

/**
 * Reads the declaration, builds the pack from it and writes the artifact.
 *
 * **The diagnosis copy is a value in `src/pack/misconception-copy.ts`**, not a
 * file this script reads: `packages/server` issues packs inside a request and
 * needs the same words, and one source is the only way the two agree.
 *
 * **An authored path is resolved relative to the declaration**, so the
 * declaration is portable and the path is data rather than a constant compiled
 * into this file.
 *
 * **The artifact is written through a temporary file.** `> out` truncates
 * before the producer has run, so a refusal — or an unreadable source — used to
 * leave the committed artifact destroyed and the tree dirty for an unrelated
 * reason; `scripts/dump-schema.sh` did exactly that, which is why this does
 * not. A failed write unlinks the temporary and rethrows, and if that unlink
 * also fails there is nothing to clean up: the original is untouched either
 * way.
 */
function main(): void {
  const misconceptions = misconceptionCopy();
  const fallbackCopy = fallbackDiagnosis();

  const declaration = parseDeclaration(
    JSON.parse(readFileSync(DECLARATION, "utf8")),
  );

  const skillIds = skillIdsOfItemSources(declaration);

  const { pack, report } = buildPack(declaration, {
    registry: CORE_REGISTRY,
    readAuthored: (relative) =>
      readFileSync(path.resolve(path.dirname(DECLARATION), relative), "utf8"),
    fallbacks: new Map([...skillIds].map((id) => [id, fallbackCopy])),
    misconceptions,
  });

  mkdirSync(path.dirname(OUT), { recursive: true });
  const temporary = `${OUT}.tmp`;
  try {
    writeFileSync(temporary, `${JSON.stringify(pack, null, 2)}\n`, "utf8");
    renameSync(temporary, OUT);
  } catch (cause) {
    try {
      unlinkSync(temporary);
    } catch {}
    throw cause;
  }

  const puzzles = describePuzzles(report.puzzleKinds);
  const families = [...report.byFamily.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([kind, n]) => `${kind} ${n}`)
    .join(", ");
  // eslint-disable-next-line no-console
  console.log(
    `pack: ${pack.items.length} items (${report.generated} generated, ` +
      `${report.authored} authored) — ${families}\n` +
      `      ${report.diagnosed} carry distractors, ${pack.items.length - report.diagnosed} do not\n` +
      `      ${puzzles}`,
  );
}

/**
 * Reports a refusal and stops the build.
 *
 * A refusal is content that needs fixing, not a crash to debug: one line, and a
 * non-zero exit so a build stops rather than committing nothing.
 */
function refuse(cause: unknown): void {
  process.stderr.write(`build:pack refused — ${(cause as Error).message}\n`);
  process.exitCode = 1;
}

try {
  main();
} catch (cause) {
  refuse(cause);
}
