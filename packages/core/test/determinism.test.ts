import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";
import { describe, expect, it } from "vitest";

/**
 * The core performs no ambient IO.
 *
 * `ARCHITECTURE.md` §3 calls this "the check nobody proposed and that actually
 * protects determinism", and it is right: the server must reconstruct the exact
 * problem years later, on a different Node, and a single `Math.random()` makes
 * that impossible in a way no type checks and no review reliably catches.
 *
 * **An AST walk rather than `no-restricted-globals`,** which is what §3 and the
 * plan both name. Two reasons, and the second is the real one:
 *
 * 1. There is no ESLint anywhere in this repository. Adding it, its config and
 *    its plugins to catch six identifiers is a lot of moving parts.
 * 2. **A flat ban cannot scope a permission.** Glicko needs `Math.exp`,
 *    `Math.log`, `Math.pow` and `Math.fround`; the generators must not inherit
 *    them, because a generator that reaches for a transcendental is a generator
 *    whose output depends on a libm nobody pinned. This gate permits them under
 *    `src/rating/` and refuses them everywhere else, which `no-restricted-globals`
 *    has no way to express.
 */

/** Bare identifiers that must not appear at all. */
const BANNED_IDENTIFIERS = ["Date", "performance", "Intl"] as const;

/** Property accesses that must not appear at all. */
const BANNED_PROPERTIES = [
  "Math.random",
  "crypto.randomUUID",
  ".toLocaleString",
] as const;

/**
 * Permitted **only** under `src/rating/`. Glicko is defined in terms of these;
 * nothing else here has any business with a transcendental.
 */
const RATING_ONLY_PROPERTIES = [
  "Math.exp",
  "Math.log",
  "Math.sqrt",
  "Math.pow",
  "Math.fround",
] as const;

const SRC = fileURLToPath(new URL("../src", import.meta.url));

/**
 * A synthetic source that violates the gate twice over, so the walker can be
 * shown to bite.
 *
 * Every assertion about the real tree passes for a walker that finds nothing
 * because it is broken. Scanning this is the cheapest way to tell the two
 * apart without adding a violation to shipped source.
 */
const PROBE_SOURCE = "export const n = () => Math.random() + Date.now();";

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const full = path.join(directory, entry);
    if (statSync(full).isDirectory()) return sourceFiles(full);
    return full.endsWith(".ts") ? [full] : [];
  });
}

/**
 * True for the `y` in `x.y` — a property name, not a reference to a global.
 *
 * The rule is deliberately "unless it is the property NAME", so `obj.Date` is
 * ignored and `Date.anything` is not. The first attempt asked
 * `!isPropertyAccessExpression(parent)` instead, which skipped the most likely
 * violation in the language: in `Date.now()`, `Date` is the *expression* of the
 * property access, so that guard excluded it — and `Date.now` is not in the
 * banned-property list either. The control test at the bottom of this file is
 * what found it.
 */
function isPropertyName(node: ts.Identifier): boolean {
  const parent = node.parent;
  return (
    (ts.isPropertyAccessExpression(parent) && parent.name === node) ||
    (ts.isPropertyAssignment(parent) && parent.name === node) ||
    (ts.isPropertySignature(parent) && parent.name === node)
  );
}

interface Sighting {
  readonly file: string;
  readonly line: number;
  readonly what: string;
}

/** Every banned or scoped construct in one file, with its line. */
function scan(file: string): { sightings: Sighting[]; nodes: number } {
  const text = readFileSync(file, "utf8");
  const source = ts.createSourceFile(file, text, ts.ScriptTarget.ES2023, true);
  const relative = path.relative(SRC, file);
  const inRating = relative.startsWith(`rating${path.sep}`);
  const sightings: Sighting[] = [];
  let nodes = 0;

  const at = (node: ts.Node): number =>
    source.getLineAndCharacterOfPosition(node.getStart(source)).line + 1;

  const visit = (node: ts.Node): void => {
    nodes += 1;

    if (ts.isIdentifier(node) && !isPropertyName(node)) {
      const name = node.text;
      if ((BANNED_IDENTIFIERS as readonly string[]).includes(name)) {
        sightings.push({ file: relative, line: at(node), what: name });
      }
    }

    if (ts.isPropertyAccessExpression(node)) {
      const spelled = `${node.expression.getText(source)}.${node.name.text}`;
      const suffix = `.${node.name.text}`;
      if (
        (BANNED_PROPERTIES as readonly string[]).includes(spelled) ||
        (BANNED_PROPERTIES as readonly string[]).includes(suffix)
      ) {
        sightings.push({ file: relative, line: at(node), what: spelled });
      }
      if (
        !inRating &&
        (RATING_ONLY_PROPERTIES as readonly string[]).includes(spelled)
      ) {
        sightings.push({
          file: relative,
          line: at(node),
          what: `${spelled} (permitted only under src/rating/)`,
        });
      }
    }

    ts.forEachChild(node, visit);
  };

  visit(source);
  return { sightings, nodes };
}

describe("the core performs no ambient IO", () => {
  const files = sourceFiles(SRC);
  const scans = files.map((file) => scan(file));

  it("walked a real tree, because a mistyped root reports nothing and looks exactly like a clean codebase (PROC-10)", () => {
    expect(files.length).toBeGreaterThan(0);
    const nodes = scans.reduce((sum, s) => sum + s.nodes, 0);
    expect(nodes).toBeGreaterThan(0);
    // eslint-disable-next-line no-console
    console.log(
      `  determinism · walked ${files.length} files, ${nodes} AST nodes`,
    );
  });

  it("reaches for no clock, no randomness and no locale", () => {
    const sightings = scans.flatMap((s) => s.sightings);
    expect(
      sightings.map((s) => `${s.file}:${s.line} ${s.what}`),
      "the core reached for something ambient",
    ).toEqual([]);
  });

  it("sees a violation that is there", () => {
    const probe = ts.createSourceFile(
      "probe.ts",
      PROBE_SOURCE,
      ts.ScriptTarget.ES2023,
      true,
    );
    const found: string[] = [];
    const visit = (node: ts.Node): void => {
      if (ts.isPropertyAccessExpression(node)) {
        const spelled = `${node.expression.getText(probe)}.${node.name.text}`;
        if ((BANNED_PROPERTIES as readonly string[]).includes(spelled)) {
          found.push(spelled);
        }
      }
      if (ts.isIdentifier(node) && !isPropertyName(node)) {
        if ((BANNED_IDENTIFIERS as readonly string[]).includes(node.text)) {
          found.push(node.text);
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(probe);

    expect(found).toContain("Math.random");
    expect(found).toContain("Date");
  });
});
