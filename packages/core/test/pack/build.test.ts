import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import {
  answerDigest,
  canonicalize,
  renderCanonicalAnswer,
  type DiagnosisCopy,
} from "@akimath/contract";
import { describe, expect, it } from "vitest";

import { CORE_REGISTRY } from "../../src/templates/index.js";
import { rederive, registryOf } from "../../src/registry.js";
import type { Template } from "../../src/template.js";
import { buildPack } from "../../src/pack/build.js";
import { parseDeclaration } from "../../src/pack/declaration.js";
import { misconceptionCopy } from "../../src/pack/misconceptions.js";
import { seedAt } from "../../src/pack/seeds.js";
import { AUTHORED_PACK_PATH } from "../authored-pack.js";

const AUTHORED_PATH = "../../app/assets/packs/starter.json";
const AUTHORED = readFileSync(AUTHORED_PACK_PATH, "utf8");

const FALLBACK: DiagnosisCopy = {
  misconception: "sin_diagnostico",
  steps: ["Vuelve a leer el reto.", "Comprueba tu resultado."],
  explain: "Aquí va el razonamiento completo, paso por paso, sin regaños.",
};

const MISCONCEPTIONS = misconceptionCopy();

const inputs = (fallbacks: ReadonlyMap<number, DiagnosisCopy> = new Map([[1, FALLBACK]])) => ({
  misconceptions: MISCONCEPTIONS,
  registry: CORE_REGISTRY,
  readAuthored: (path: string) => {
    if (path !== AUTHORED_PATH) throw new Error(`unexpected path ${path}`);
    return AUTHORED;
  },
  fallbacks,
});

const declaration = (over: Record<string, unknown> = {}) =>
  parseDeclaration({
    pack_salt: "a1b2c3d4e5f60718293a4b5c6d7e8f90",
    seed_base: "1000",
    issued_at: "2026-08-18T00:00:00.000Z",
    expires_at: "2026-11-18T00:00:00.000Z",
    sources: [
      { kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 5 },
      { kind: "authored", path: AUTHORED_PATH, skill_id: 1 },
    ],
    ...over,
  });

/**
 * One template exists and five families are authored, so a wholly generated
 * pack would offer a player one kind of question. That is what the six-family
 * case guards, and it is the regression a source list must not reintroduce.
 *
 * **PROC-11.** The refusal case below asserted `not.toThrow()` first, which is
 * a tautology: deleting the validation entirely left it green. It has to feed
 * something invalid and watch the build refuse it.
 */
describe("a pack is assembled from sources", () => {
  it("carries every item from both kinds of source", () => {
    const { pack, report } = buildPack(declaration(), inputs());

    expect(report.generated).toBe(5);
    expect(report.authored).toBe(70);
    expect(pack.items).toHaveLength(75);
  });

  it("keeps the declared order, so the pack's order stays a product decision", () => {
    const { pack } = buildPack(declaration(), inputs());
    expect(pack.items.slice(0, 5).every((i) => i.stimulus.kind === "arithmetic")).toBe(true);
  });

  it("still offers all six families, which is the point of sources", () => {
    const { report } = buildPack(declaration(), inputs());

    // eslint-disable-next-line no-console
    console.log(
      `  pack build · ${report.generated} generated + ${report.authored} authored → ` +
        [...report.byFamily.entries()].sort().map(([k, n]) => `${k} ${n}`).join(", "),
    );
    expect(report.byFamily.size).toBe(6);
  });

  it("refuses to return a pack the frozen validator rejects, here as `unknown_index_out_of_range` from `parseStimulus` — the lift is an envelope concern and does not read inside a payload", () => {
    const liftsButFailsStimulusValidation = JSON.stringify({
      items: [
        {
          id: "hole-off-the-end",
          ladder_step: 1,
          answer: "8",
          stimulus: { kind: "numberSeries", payload: { terms: [2, 4, 6], unknown_index: 99 } },
        },
      ],
    });

    expect(() =>
      buildPack(declaration({ sources: [{ kind: "authored", path: "broken.json", skill_id: 1 }] }), {
        ...inputs(),
        readAuthored: () => liftsButFailsStimulusValidation,
      }),
    ).toThrow(/unknown_index_out_of_range/);
  });
});

/**
 * A hand-authored board is exactly the input where knowing *which* one is wrong
 * saves the afternoon, because `parsePack`'s tag names only the fault.
 *
 * `checkCageCoverage` is the frozen validator's, and the coverage case below is
 * what says the builder actually runs it rather than trusting the file.
 */
describe("a pack may carry puzzles", () => {
  const kenken = JSON.stringify({
    puzzles: [
      {
        kind: "kenken",
        payload: {
          board: { size: 3, blocked: [], given: [], solution: [[1, 2, 3], [2, 3, 1], [3, 1, 2]] },
          cages: [
            { cells: [{ row: 0, col: 0 }, { row: 1, col: 0 }], operation: "+", target: 3 },
            { cells: [{ row: 0, col: 1 }, { row: 0, col: 2 }], operation: "-", target: 1 },
            { cells: [{ row: 1, col: 1 }, { row: 2, col: 1 }], operation: "-", target: 2 },
            { cells: [{ row: 1, col: 2 }, { row: 2, col: 2 }], operation: "+", target: 3 },
            { cells: [{ row: 2, col: 0 }], operation: "+", target: 3 },
          ],
        },
        tutorial_steps: ["Cada fila lleva 1, 2 y 3."],
        reference_sheet: ["Nada se repite en su fila."],
      },
    ],
  });

  const withPuzzles = (file: string) =>
    buildPack(
      declaration({
        sources: [
          { kind: "authored", path: AUTHORED_PATH, skill_id: 1 },
          { kind: "puzzles", path: "puzzles.json" },
        ],
      }),
      {
        ...inputs(),
        readAuthored: (path: string) => (path === "puzzles.json" ? file : AUTHORED),
      },
    );

  it("carries an authored board through to the pack", () => {
    const { pack, report } = withPuzzles(kenken);

    expect(pack.puzzles).toHaveLength(1);
    expect(pack.puzzles[0]?.kind).toBe("kenken");
    expect(report.puzzleKinds).toEqual(["kenken"]);
  });

  it("reports no puzzles when none were declared, so the gap stays visible", () => {
    expect(buildPack(declaration(), inputs()).report.puzzleKinds).toEqual([]);
  });

  it("refuses a board the frozen envelope rejects, naming the puzzle", () => {
    const missingCopy = JSON.stringify({
      puzzles: [{ kind: "kenken", payload: {}, tutorial_steps: [], reference_sheet: [] }],
    });
    expect(() => withPuzzles(missingCopy)).toThrow(/puzzle 0/);
  });

  it("refuses a cage that does not cover the board, running the frozen validator", () => {
    const gap = JSON.parse(kenken) as { puzzles: { payload: { cages: unknown[] } }[] };
    gap.puzzles[0]!.payload.cages = [gap.puzzles[0]!.payload.cages[0]];
    expect(() => withPuzzles(JSON.stringify(gap))).toThrow();
  });
});

/**
 * **The bug this group was written for, #50.** `answer.shape` and the spelling
 * the digest is taken over were computed separately, and the spelling always
 * passed a denominator — so a whole answer of −9 was stored as the digest of
 * `-9/1` while the shape said `integer`. A player typing `-9` canonicalises to
 * `-9`, whose digest is different, so **every generated item in the built pack
 * was ungradeable.** Latent only because the app ships the authored pack; it
 * would have surfaced the day the built one did. The shape is **derived from**
 * the spelling now, by `@akimath/contract`'s `storedAnswer`, so the pack builder
 * and the server make one decision about shape and spelling rather than two
 * that can come apart.
 *
 * **The distractors are the second half of the same bug.** The guard in
 * `distractors.ts` compares strings, so it only works if `build.ts` hands it
 * the same spelling it digests: the correct answer went in as `0/1` while the
 * predictions were spelled `0`, and a pack could ship a distractor telling a
 * right answer it was a known mistake. Checked here rather than in
 * `diagnosis.test.ts`, because the unit already passes — what needed pinning is
 * that the builder agrees with itself, and zero distractors would make that
 * sweep vacuous, so it reports its own count (PROC-10).
 *
 * **Two synthetic templates appear below, and both earn their place.** The one
 * shipped template returns integers, so the fraction branch is unreachable
 * through it and hardcoding the integer shape passed the whole suite; a registry
 * of one synthetic template exercises the other side. The second declares a
 * different `skillId`, because the declaration no longer states a skill for a
 * template source — a template saying so is now the only way two skills can
 * appear.
 */
describe("a generated answer is shaped by what the template produced", () => {
  it("calls a fractional answer a fraction", () => {
    const fractional: Template = {
      id: "spike.fraction",
      version: 1,
      skillId: 1,
      generate: (ref) => ({
        prompt: [],
        answer: { numerator: 5n, denominator: 4n },
        ladderStep: ref.ladderStep,
        operator: "+",
        left: { num: 1, den: 2 },
        right: { num: 3, den: 4 },
      }),
    };

    const { pack } = buildPack(
      declaration({
        sources: [{ kind: "template", template_id: "spike.fraction", template_version: 1, ladder_step: 2, count: 1 }],
      }),
      { ...inputs(), registry: registryOf([fractional]) },
    );

    expect(pack.items[0]?.answer.shape).toBe("fraction");
  });

  it("and spells it the way a learner types it, so the digest matches", () => {
    const declared = declaration({
      sources: [{ kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 10 }],
    });
    const { pack } = buildPack(declared, inputs());

    expect(pack.items).toHaveLength(10);
    pack.items.forEach((item, index) => {
      const generated = rederive(CORE_REGISTRY, {
        templateId: "arith.integer.subtract",
        templateVersion: 2,
        seed: seedAt(declared.seedBase, index),
        ladderStep: 3,
      });
      const typedOnTheKeypad = renderCanonicalAnswer(generated.answer.numerator);
      const canonical = canonicalize(typedOnTheKeypad);
      expect(canonical.ok, typedOnTheKeypad).toBe(true);
      expect(item.answer.shape).toBe("integer");
      expect(item.answer.digest, `item ${index} answers ${typedOnTheKeypad}`).toBe(
        answerDigest(pack.pack_salt, canonical.ok ? canonical.value : ""),
      );
    });
  });

  it("and no distractor it ships collides with the answer it sits beside", () => {
    const { pack } = buildPack(declaration({
      sources: [{ kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 10 }],
    }), inputs());

    let distractors = 0;
    for (const item of pack.items) {
      for (const distractor of item.diagnosis?.distractors ?? []) {
        distractors += 1;
        expect(distractor.digest).not.toBe(item.answer.digest);
      }
    }
    expect(distractors).toBeGreaterThan(0);
    console.log(`  distractor collision · checked ${distractors} distractor(s)`);
  });

  it("calls a whole answer an integer", () => {
    const { pack } = buildPack(declaration({
      sources: [{ kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 1 }],
    }), inputs());
    expect(pack.items[0]?.answer.shape).toBe("integer");
  });
});

/**
 * **req-builder-deterministic.** A seed base that is accepted and then ignored
 * would satisfy the byte-identity claim perfectly, so one case moves the base
 * and watches the items move with it.
 *
 * The seed counter spans the build rather than each source: per-source counters
 * would issue the same item twice and the pack would still look fine.
 */
describe("the same declaration always produces the same pack", () => {
  it("two builds are byte-identical", () => {
    const a = JSON.stringify(buildPack(declaration(), inputs()).pack);
    const b = JSON.stringify(buildPack(declaration(), inputs()).pack);
    expect(a).toBe(b);
  });

  it("a different seed base produces different items", () => {
    const a = buildPack(declaration(), inputs()).pack.items.slice(0, 5);
    const b = buildPack(declaration({ seed_base: "999999" }), inputs()).pack.items.slice(0, 5);
    expect(JSON.stringify(a)).not.toBe(JSON.stringify(b));
  });

  it("two template sources never share a seed", () => {
    const { pack } = buildPack(
      declaration({
        sources: [
          { kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 3 },
          { kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 3 },
        ],
      }),
      inputs(),
    );
    const rendered = pack.items.map((i) => JSON.stringify(i.stimulus));
    expect(new Set(rendered).size).toBe(6);
  });
});

/**
 * The authored answers are the ones nameable from outside the builder, so they
 * are the ones swept for, and their count is asserted as well — a sweep that
 * checked nothing would otherwise pass.
 */
describe("no answer travels in the clear", () => {
  it("no item's canonical answer appears anywhere in the pack", () => {
    const { pack } = buildPack(declaration(), inputs());
    const serialised = JSON.stringify(pack);

    const authoredAnswers = (JSON.parse(AUTHORED) as { items: { answer: string }[] }).items.map(
      (i) => i.answer,
    );
    const leaked = authoredAnswers.filter((a) => serialised.includes(`"${a}"`));

    expect(leaked).toEqual([]);
    expect(authoredAnswers.length).toBe(70);
  });
});

/**
 * The frozen validator refuses a skill with items and no fallback too, but it
 * refuses it as `missing_skill_fallback` after assembly. Failing here names the
 * skill.
 */
describe("every skill can answer for itself", () => {
  it("emits a node and a fallback for each skill an item names", () => {
    const { pack } = buildPack(declaration(), inputs());
    expect(pack.skill_nodes.map((n) => n.skill_id)).toEqual([1]);
    expect(pack.skill_fallbacks.map((f) => f.skill_id)).toEqual([1]);
  });

  it("refuses a skill that has items but no fallback copy, naming the skill", () => {
    expect(() => buildPack(declaration(), inputs(new Map()))).toThrow(/skill 1/);
  });

  it("declares a node for every distinct skill, not just the first", () => {
    const otherSkill: Template = {
      id: "spike.other-skill",
      version: 1,
      skillId: 4,
      generate: (ref) => ({
        prompt: [],
        answer: { numerator: 2n, denominator: 1n },
        ladderStep: ref.ladderStep,
        operator: "-",
        left: { num: 5, den: 1 },
        right: { num: 3, den: 1 },
      }),
    };

    const { pack } = buildPack(
      declaration({
        sources: [
          { kind: "authored", path: AUTHORED_PATH, skill_id: 1 },
          { kind: "template", template_id: "spike.other-skill", template_version: 1, ladder_step: 3, count: 2 },
        ],
      }),
      {
        ...inputs(new Map([[1, FALLBACK], [4, FALLBACK]])),
        registry: registryOf([otherSkill]),
      },
    );
    expect(pack.skill_nodes.map((n) => n.skill_id)).toEqual([1, 4]);
  });
});
