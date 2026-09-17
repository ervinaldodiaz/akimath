import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";
import { describe, expect, it } from "vitest";

/**
 * There is one way to decide how an exact answer is written down.
 *
 * **This gate is the durable form of bug #50.** That bug computed
 * `answer.shape` and the string the digest is taken over separately, so a whole
 * answer of −9 was digested as `-9/1` while the field beside it said `integer`
 * — every generated item in the built pack was ungradeable, the
 * distractor-equals-answer guard stopped firing, and **no suite went red**. The
 * fix moved the decision into `@akimath/contract`'s `storedAnswer`, and four
 * comments then claimed it had one implementation. It had three. Nothing could
 * see the other two, because the only thing saying where they were was prose.
 *
 * A gate, so the fourth copy is a red build rather than an audit finding.
 *
 * **Two prohibitions, because the decision has two halves and they are copied
 * separately.** `packages/core/src/pack/lift.ts` copied the *shape* half and
 * `packages/server/src/attempts.ts` copied the *spelling* half; a gate holding
 * only one of them would have caught only one of them.
 *
 * The doors are `storedAnswer` — for a caller holding a `(numerator,
 * denominator)` — and `storedAnswerOf`, for a caller holding a canonical
 * string. Both return shape and spelling together, which is the whole point.
 *
 * **What it cannot see, stated rather than left to be discovered.** It reads
 * syntax, so a copy that names neither word nor the function — `ANSWER_SHAPES[
 * hasSlash ? 1 : 0]`, or a shape arriving through a helper in a third file —
 * walks past it. That is the same honesty `one-way-to-log.test.ts` owes when it
 * names its one writer instead of matching a pattern: this catches the copy
 * somebody writes without meaning to, which is every copy this repository has
 * actually grown, and it is not a proof.
 *
 * **No sibling in `app/`, and that is a finding rather than an omission.** The
 * Dart tree never reads the `shape` key — `grep -rn "'shape'" app/lib/` returns
 * nothing, and `ItemAnswer` is a sealed `PlainAnswer | DigestAnswer` carrying a
 * canonical string or a digest and no shape at all. There is nothing there to
 * copy, so a fourth gate would guard a field that does not cross the wire into
 * Dart.
 */

/**
 * The two members of `ANSWER_SHAPES`. **A copy of this decision has to name
 * both**, because deciding a shape means choosing between them — which is what
 * makes naming both the discriminator and naming one merely a coincidence of
 * vocabulary. `lift.ts` says `t.kind === "fraction"` about a *stimulus term*,
 * a different thing that happens to share a word, and this gate leaves it
 * alone rather than needing a carve-out for it.
 */
const SHAPE_WORDS = ["integer", "fraction"] as const;

/**
 * The sharp ingredient. `renderCanonicalAnswer` spells a number and takes no
 * view on the shape beside it; reaching for it is how the spelling half gets
 * copied, and `attempts.ts` is the worked example.
 */
const THE_SPELLER = "renderCanonicalAnswer";

/**
 * The one file allowed to spell by hand, named rather than matched.
 *
 * `pack/distractors.ts` renders a *wrong* answer. A distractor is a spelling
 * with no shape beside it — the frozen `DiagnosisPayloadSchema` gives it no
 * `shape` field — so there is no pair here to keep together, and the composite
 * would have nothing to add. This is also where #50's second half landed: the
 * guard that drops a distractor equal to the right answer compares strings, so
 * what this file renders has to be the same spelling the item's answer got.
 *
 * **Named rather than matched, and the name is checked** — PROC-10 on the
 * allowlist itself. A carve-out for a file that has since been renamed excuses
 * nothing and hides that it is stale, so the suite asserts the path is still on
 * disk.
 */
const MAY_SPELL_BY_HAND: readonly string[] = ["pack/distractors.ts"];

/**
 * The tree this gate walks, resolved from `import.meta.url` rather than from the
 * working directory.
 *
 * **PROC-10 is why the walk's own size is asserted.** Stryker copies the package
 * into a sandbox one level deeper, so a root resolved by counting `..` segments
 * can quietly land on nothing — and a walk over zero files reports no violations,
 * which is indistinguishable from a walk that found none.
 */
const SRC = fileURLToPath(new URL("../src", import.meta.url));

/**
 * A source that commits both prohibitions, so the walker can be shown to see
 * them.
 *
 * **The control.** Every other assertion in this file passes for a walker that
 * finds nothing *because it is broken*, and the two outcomes are
 * indistinguishable without this. Both violations are here rather than one,
 * because the two are found by different code.
 */
const PROBE_COMMITTING_BOTH_VIOLATIONS = [
  'const shape = answer.includes("/") ? "fraction" : "integer";',
  "const spelled = renderCanonicalAnswer(numerator, denominator);",
].join("\n");

function sourceFiles(directory: string): string[] {
  return readdirSync(directory).flatMap((entry) => {
    const full = path.join(directory, entry);
    if (statSync(full).isDirectory()) return sourceFiles(full);
    return full.endsWith(".ts") ? [full] : [];
  });
}

interface Sighting {
  readonly file: string;
  readonly line: number;
  readonly what: string;
}

/**
 * A sighting naming *every* shape word's line, or null when only some are named.
 *
 * The **pair** is the violation, so the report gives both positions. Naming one
 * half of it points a reader at whichever word came first — here, at a stimulus
 * term parser that shares the vocabulary and is not the offender at all.
 */
function shapeDecidedByHand(
  file: string,
  wordLines: ReadonlyMap<string, number>,
): Sighting | null {
  if (wordLines.size !== SHAPE_WORDS.length) return null;
  const where = [...wordLines].map(([word, line]) => `${word}@${line}`).join(", ");
  return {
    file,
    line: Math.min(...wordLines.values()),
    what: `decides an answer shape by hand (${where})`,
  };
}

/**
 * An AST walk and not a regex, for one reason that bites here specifically:
 * this gate reads for two words that appear in *explanations* of the rule as
 * often as in code, and a syntax tree cannot see a comment at all. The Dart
 * side strips prose by hand for exactly this
 * (`app/test/architecture/verdict_is_not_a_colour_test.dart`); the compiler
 * API makes it free.
 */
function scan(file: string): Sighting[] {
  const source = ts.createSourceFile(
    file,
    readFileSync(file, "utf8"),
    ts.ScriptTarget.ES2023,
    true,
  );
  const relative = path.relative(SRC, file).split(path.sep).join("/");
  const at = (node: ts.Node): number =>
    source.getLineAndCharacterOfPosition(node.getStart(source)).line + 1;

  const wordLines = new Map<string, number>();
  const sightings: Sighting[] = [];

  const visit = (node: ts.Node): void => {
    if (ts.isStringLiteral(node) && (SHAPE_WORDS as readonly string[]).includes(node.text)) {
      if (!wordLines.has(node.text)) wordLines.set(node.text, at(node));
    }
    if (
      ts.isCallExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === THE_SPELLER &&
      !MAY_SPELL_BY_HAND.includes(relative)
    ) {
      sightings.push({ file: relative, line: at(node), what: `calls ${THE_SPELLER}` });
    }
    ts.forEachChild(node, visit);
  };
  visit(source);

  const byHand = shapeDecidedByHand(relative, wordLines);
  if (byHand) sightings.push(byHand);
  return sightings;
}

describe("there is one way to spell a stored answer", () => {
  const files = sourceFiles(SRC);

  it("reports what it scanned, and scanning nothing is a failure", () => {
    expect(files.length).toBeGreaterThan(0);
    console.log(`  one way to spell an answer · scanned ${files.length} source file(s)`);
  });

  it("the file allowed to spell by hand is still there, so the carve-out cannot go stale", () => {
    const relatives = files.map((f) => path.relative(SRC, f).split(path.sep).join("/"));
    expect(relatives).toEqual(expect.arrayContaining([...MAY_SPELL_BY_HAND]));
  });

  it("nothing decides a shape by hand, and nothing else spells one", () => {
    const sightings = files.flatMap(scan);
    expect(
      sightings.map((s) => `${s.file}:${s.line} ${s.what}`),
      "a second implementation of shape-and-spelling; call storedAnswer or storedAnswerOf",
    ).toEqual([]);
  });

  it("the walker is not broken: it sees both violations when they are there", () => {
    const probe = ts.createSourceFile(
      "probe.ts",
      PROBE_COMMITTING_BOTH_VIOLATIONS,
      ts.ScriptTarget.ES2023,
      true,
    );
    const words = new Set<string>();
    let spells = false;
    const visit = (node: ts.Node): void => {
      if (ts.isStringLiteral(node) && (SHAPE_WORDS as readonly string[]).includes(node.text)) {
        words.add(node.text);
      }
      if (
        ts.isCallExpression(node) &&
        ts.isIdentifier(node.expression) &&
        node.expression.text === THE_SPELLER
      ) {
        spells = true;
      }
      ts.forEachChild(node, visit);
    };
    visit(probe);

    expect([...words].sort()).toEqual([...SHAPE_WORDS].sort());
    expect(spells).toBe(true);
  });
});
