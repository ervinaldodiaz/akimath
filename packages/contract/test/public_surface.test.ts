import { describe, expect, it } from "vitest";

import * as contract from "../src/index.js";

/**
 * `design.md` D9 gives the package a public surface that re-exports and holds
 * no logic of its own. `f1-contract-emitter` inherits this package, so the
 * names it can reach are part of the contract, not an implementation detail.
 *
 * **The last case is set equality, because the others cannot see an addition.**
 * Each of them checks a name it already knows, so a new export would ship with
 * no test at all — which is how `renderCanonicalAnswer` would have arrived
 * unnoticed. Writing the list down was itself the finding: every schema,
 * `canonicalJson`, `checkDistractors`, `declaredState` and the parsers had no
 * surface coverage whatever. Adding to the surface should be a decision, and
 * this is what makes it one. The count is reported rather than stated, because
 * `[] === []` also passes for a module that failed to load (PROC-10, PROC-11).
 *
 * **`storedAnswer` and `storedAnswerOf` are two doors on one decision** — shape
 * and spelling, decided together, for the two inputs a caller can hold. Who
 * derives a stored answer is not asserted here in prose: `packages/core`'s and
 * `packages/server`'s `one-way-to-spell-an-answer.test.ts` walk their own ASTs
 * for a fourth copy, which is CMT-4's gate rather than a sentence that goes
 * stale (this one did, naming two callers where there were three).
 */
describe("the package's public surface", () => {
  it("exposes the pack parser and its format version", () => {
    expect(contract.PACK_FORMAT_VERSION).toBe(1);
    expect(typeof contract.parsePack).toBe("function");
  });

  it("exposes both canonicalization directions, the renderer and the fold map", () => {
    expect(typeof contract.canonicalize).toBe("function");
    expect(typeof contract.requireStoredCanonical).toBe("function");
    expect(typeof contract.renderCanonicalAnswer).toBe("function");
    expect(contract.CHAR_MAP["−"]).toBe("-");
  });

  it("exposes the digest, which is the only door pack content has to one", () => {
    expect(typeof contract.answerDigest).toBe("function");
    expect(typeof contract.digestStoredAnswer).toBe("function");
  });

  it("exposes the diagnosis lookup and the canon golden builder", () => {
    expect(typeof contract.lookupDiagnosis).toBe("function");
    expect(typeof contract.buildCanonGolden).toBe("function");
  });

  it("exposes every closed enum the format freezes", () => {
    expect(contract.STIMULUS_KINDS.length).toBe(6);
    expect(contract.PUZZLE_KINDS.length).toBe(5);
    expect(contract.KEYPAD_LAYOUTS.length).toBe(3);
    expect(contract.SKILL_NODE_STATES.length).toBe(4);
    expect(contract.ANSWER_SHAPES.length).toBe(2);
  });

  it("exposes exactly this surface and no more", () => {
    const exported = Object.keys(contract).sort();

    expect(exported).toEqual(
      [
        "ANSWER_SHAPES",
        "AnswerSpecSchema",
        "CANON_INPUTS",
        "CHAR_MAP",
        "DIGEST_GOLDEN_SALT",
        "DIGEST_INPUTS",
        "DIAGNOSIS_VERSION",
        "DiagnosisCopySchema",
        "DiagnosisPayloadSchema",
        "DigestSchema",
        "ItemSchema",
        "KEYPAD_LAYOUTS",
        "KeypadLayoutSchema",
        "PACK_FORMAT_VERSION",
        "PUZZLE_KINDS",
        "PUZZLE_PAYLOAD_SCHEMAS",
        "PackSchema",
        "PuzzleEnvelopeSchema",
        "SKILL_NODE_STATES",
        "STIMULUS_KINDS",
        "STIMULUS_PAYLOAD_SCHEMAS",
        "SkillFallbackSchema",
        "SkillNodeSchema",
        "StimulusEnvelopeSchema",
        "answerDigest",
        "buildCanonGolden",
        "buildDigestGolden",
        "canonicalJson",
        "canonicalize",
        "checkDistractors",
        "declaredState",
        "digestStoredAnswer",
        "fallbackForSkill",
        "lookupDiagnosis",
        "parsePack",
        "parsePuzzle",
        "parseStimulus",
        "renderCanonicalAnswer",
        "requireStoredCanonical",
        "storedAnswer",
        "storedAnswerOf",
      ].sort(),
    );

    expect(exported.length).toBeGreaterThan(0);
    // eslint-disable-next-line no-console
    console.log(`  contract public surface · ${exported.length} exports`);
  });
});
