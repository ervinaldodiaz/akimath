import { describe, expect, it } from "vitest";

import { MISCONCEPTION_COPY } from "../../src/pack/misconception-copy.js";
import {
  FALLBACK_MISCONCEPTION,
  fallbackDiagnosis,
  FORBIDDEN_WORDS,
  misconceptionCopy,
  parseMisconceptions,
  scoldings,
} from "../../src/pack/misconceptions.js";

/**
 * The copy is a value now, and this is what it used to get from being a file.
 *
 * `test/pack/cli.test.ts` used to point the build script at a copy file with no
 * fallback and assert it exited 1. That scenario cannot happen any more — there
 * is no file to point at — so the guarantee moved here rather than evaporating:
 * `fallbackDiagnosis()` throws rather than handing back undefined, and the case
 * below holds it to that. `missing_skill_fallback` is a frozen rejection tag, so
 * a skill with items and no fallback makes the whole pack invalid — which is why
 * the fallback is checked at load and not at the moment a request needs it.
 *
 * **Every claim here has its control**, because "the copy parses" is otherwise a
 * claim about a parser that might accept anything.
 *
 * The one rule the copy itself has to keep is that Aki does not tell a learner
 * off, and that is asked of the module's own list of words rather than of a
 * regex written here: a second list is a second thing to keep in agreement, and
 * this one would quietly stop matching the day a word is added. The anchors on
 * the identifier pattern are load-bearing the same way they are in the server's
 * uuid patterns — without `^` and `$` a key with anything around it passes.
 */
describe("the diagnosis copy is validated, not trusted", () => {
  it("parses, and reports how many entries it checked", () => {
    const parsed = misconceptionCopy();

    expect(parsed.size).toBe(Object.keys(MISCONCEPTION_COPY).length);
    expect(parsed.size).toBeGreaterThan(0);
    console.log(`  misconception copy · ${parsed.size} entr(ies), all parsed`);
  });

  it("every entry keeps the shape the schema demands", () => {
    for (const [id, copy] of misconceptionCopy()) {
      expect(id, id).toMatch(/^[a-z][a-z0-9_]*$/u);
      expect(copy.steps.length, id).toBeGreaterThanOrEqual(1);
      expect(copy.steps.length, id).toBeLessThanOrEqual(4);
      expect(copy.explain.length, id).toBeGreaterThan(0);
    }
  });

  it("and the parser still refuses what it always refused", () => {
    expect(() => parseMisconceptions({ "Not Snake Case": { steps: ["x"], explain: "y" } }))
      .toThrow(/snake_case/);
    expect(() => parseMisconceptions("nope")).toThrow(/must be an object/);
  });

  it("the fallback exists, because a pack without one is refused", () => {
    expect(misconceptionCopy().has(FALLBACK_MISCONCEPTION)).toBe(true);
    expect(fallbackDiagnosis().steps.length).toBeGreaterThan(0);
    expect(fallbackDiagnosis().explain).not.toBe("");
  });

  it("and nothing in it scolds", () => {
    for (const [id, copy] of misconceptionCopy()) {
      expect(scoldings([copy.explain, ...copy.steps]), id).toEqual([]);
    }
  });

  it("every forbidden word is caught on its own, so blanking one cannot pass", () => {
    expect(FORBIDDEN_WORDS.length).toBeGreaterThan(0);
    for (const word of FORBIDDEN_WORDS) {
      expect(scoldings([`Eso estuvo ${word} otra vez`]), word).toHaveLength(1);
      expect(
        () => parseMisconceptions({ a_thing: { steps: [`x ${word}`], explain: "y" } }),
        word,
      ).toThrow(/names the failure/);
    }
    console.log(`  scolding sweep · ${FORBIDDEN_WORDS.length} forbidden word(s), each proven`);
  });

  it("it catches a forbidden word inside a longer one on purpose, and reports where", () => {
    expect(scoldings(["hubo errores"])).toEqual(['"error" in "hubo errores"']);
    expect(scoldings(["ESO ESTUVO MAL"])).toHaveLength(1);
    expect(scoldings(["todo bien"])).toEqual([]);
    expect(scoldings([])).toEqual([]);
  });

  it("a key is refused unless it is exactly an identifier, and one letter is one", () => {
    for (const key of ["Uppercase", "1leading_digit", " leading_space", "trailing ", "has-dash", ""]) {
      expect(
        () => parseMisconceptions({ [key]: { steps: ["x"], explain: "y" } }),
        JSON.stringify(key),
      ).toThrow(/snake_case/);
    }
    expect(parseMisconceptions({ a: { steps: ["x"], explain: "y" } }).size).toBe(1);
  });
});
