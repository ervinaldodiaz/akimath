import { describe, expect, it } from "vitest";

import { readFixture } from "./fixture-files.js";
import {
  storedAnswer,
  storedAnswerOf,
  canonicalize,
  CHAR_MAP,
  renderCanonicalAnswer,
  requireStoredCanonical,
} from "../src/canon.js";
import { buildCanonGolden, CANON_INPUTS } from "../src/canon-vectors.js";

const ARABIC_INDIC_ZERO = "٠";
const ZERO_WIDTH_SPACE = "​";
const COMBINING_ACUTE = "́";
const MINUS_SIGN = "−";

interface RenderedShape {
  readonly numerator: bigint;
  readonly denominator?: bigint;
  readonly expected: string;
}

describe("canonicalize — learner input", () => {
  it("rejects an empty answer", () => {
    expect(canonicalize("")).toEqual({ ok: false, tag: "empty" });
  });

  it("rejects a zero denominator", () => {
    expect(canonicalize("1/0")).toEqual({ ok: false, tag: "zero_denominator" });
  });

  it("rejects an answer that is not a number", () => {
    expect(canonicalize("x+1")).toEqual({ ok: false, tag: "non_numeric" });
  });

  it("rejects an Arabic-Indic digit", () => {
    expect(canonicalize(ARABIC_INDIC_ZERO)).toEqual({ ok: false, tag: "non_ascii_digit" });
  });

  it("rejects a zero-width space rather than stripping it", () => {
    expect(canonicalize(`1${ZERO_WIDTH_SPACE}2`)).toEqual({
      ok: false,
      tag: "invisible_character",
    });
  });

  it("rejects a combining mark rather than stripping it", () => {
    expect(canonicalize(`1${COMBINING_ACUTE}`)).toEqual({ ok: false, tag: "combining_mark" });
  });

  it("folds the keypad's U+2212 minus sign to ASCII", () => {
    expect(canonicalize(`${MINUS_SIGN}5`)).toEqual({ ok: true, value: "-5" });
  });

  it("folds the answer draft's placeholder spaces away", () => {
    expect(canonicalize(" 5 ")).toEqual({ ok: true, value: "5" });
  });

  it("folds leading zeros so 007 and 7 reach the same bytes", () => {
    expect(canonicalize("007")).toEqual({ ok: true, value: "7" });
  });

  it("folds negative zero to zero", () => {
    expect(canonicalize("-0")).toEqual({ ok: true, value: "0" });
  });

  it("keeps a fraction unreduced, because 2/4 and 1/2 are different answers", () => {
    expect(canonicalize("2/4")).toEqual({ ok: true, value: "2/4" });
  });

  it("accepts a canonical fraction unchanged", () => {
    expect(canonicalize("1/2")).toEqual({ ok: true, value: "1/2" });
  });

  it("rejects a fraction with a negative denominator", () => {
    expect(canonicalize("1/-2")).toEqual({ ok: false, tag: "non_numeric" });
  });
});

describe("requireStoredCanonical — pack content", () => {
  it("rejects an empty stored answer", () => {
    expect(requireStoredCanonical("")).toEqual({ ok: false, tag: "empty" });
  });

  it("rejects a stored zero denominator", () => {
    expect(requireStoredCanonical("1/0")).toEqual({ ok: false, tag: "zero_denominator" });
  });

  it("rejects a stored answer that is not a number", () => {
    expect(requireStoredCanonical("x+1")).toEqual({ ok: false, tag: "non_numeric" });
  });

  it("rejects a stored Arabic-Indic digit", () => {
    expect(requireStoredCanonical(ARABIC_INDIC_ZERO)).toEqual({
      ok: false,
      tag: "non_ascii_digit",
    });
  });

  it("rejects a stored zero-width space", () => {
    expect(requireStoredCanonical(`1${ZERO_WIDTH_SPACE}2`)).toEqual({
      ok: false,
      tag: "invisible_character",
    });
  });

  it("rejects a stored combining mark", () => {
    expect(requireStoredCanonical(`1${COMBINING_ACUTE}`)).toEqual({
      ok: false,
      tag: "combining_mark",
    });
  });

  it("rejects a stored U+2212 that the learner direction would have folded", () => {
    expect(requireStoredCanonical(`${MINUS_SIGN}5`)).toEqual({ ok: false, tag: "not_canonical" });
  });

  it("rejects stored leading zeros that the learner direction would have folded", () => {
    expect(requireStoredCanonical("007")).toEqual({ ok: false, tag: "not_canonical" });
  });

  it("accepts a stored answer that is already canonical", () => {
    expect(requireStoredCanonical("1/2")).toEqual({ ok: true, value: "1/2" });
  });
});

describe("the committed canon.golden.json", () => {
  it("is what the code produces, not a hand-written vector", () => {
    expect(readFixture("canon.golden.json")).toEqual(JSON.parse(JSON.stringify(buildCanonGolden())));
  });

  it("records both directions for every row of the table", () => {
    const golden = buildCanonGolden();
    expect(golden.vectors.length).toBe(CANON_INPUTS.length);
    for (const vector of golden.vectors) {
      expect(vector).toHaveProperty("learner");
      expect(vector).toHaveProperty("stored");
    }
  });

  it("records the fold map the two stacks must share", () => {
    expect(buildCanonGolden().char_map).toEqual(CHAR_MAP);
  });
});

/**
 * **Why the renderer lives in `canon.ts` calling the same private join.** If
 * rendering and `requireStoredCanonical` could disagree, a pack would carry
 * answers its own validator refuses — so everything the renderer produces is
 * asserted to be storage-canonical, and the learner direction is asserted to
 * fold to the same string.
 *
 * **The shape is the caller's decision and the spelling is this module's.**
 * Guessing the shape from the value would make `renderCanonicalAnswer(4n)` and
 * `renderCanonicalAnswer(4n, 1n)` the same call.
 */
describe("rendering is the inverse of canonicalizing, by construction", () => {
  /** Whole numbers and fractions, both signs, with no subtlety in them. */
  const PLAIN: readonly RenderedShape[] = [
    { numerator: 0n, expected: "0" },
    { numerator: 7n, expected: "7" },
    { numerator: -7n, expected: "-7" },
    { numerator: 1n, denominator: 2n, expected: "1/2" },
    { numerator: -3n, denominator: 4n, expected: "-3/4" },
    { numerator: 5n, denominator: 4n, expected: "5/4" },
    { numerator: 12n, denominator: 7n, expected: "12/7" },
    { numerator: 4n, denominator: 1n, expected: "4/1" },
    { numerator: 0n, denominator: 5n, expected: "0/5" },
  ];

  /**
   * A sign on a zero magnitude is dropped, in both shapes — the rule a `-0/5`
   * defect once shipped through on the Dart side.
   */
  const ZERO_MAGNITUDE_LOSES_ITS_SIGN: readonly RenderedShape[] = [
    { numerator: -0n, denominator: 5n, expected: "0/5" },
    { numerator: 0n, denominator: -5n, expected: "0/5" },
    { numerator: -0n, expected: "0" },
  ];

  const NEGATIVE_DENOMINATOR_MOVES_ITS_SIGN: readonly RenderedShape[] = [
    { numerator: 3n, denominator: -4n, expected: "-3/4" },
    { numerator: -3n, denominator: -4n, expected: "3/4" },
  ];

  const BEYOND_A_DOUBLE: readonly RenderedShape[] = [
    { numerator: 9007199254740993n, expected: "9007199254740993" },
  ];

  /** Every shape the renderer can produce, spanning sign, zero and denominator. */
  const RENDERED: readonly RenderedShape[] = [
    ...PLAIN,
    ...ZERO_MAGNITUDE_LOSES_ITS_SIGN,
    ...NEGATIVE_DENOMINATOR_MOVES_ITS_SIGN,
    ...BEYOND_A_DOUBLE,
  ];

  it("renders the shape the format specifies", () => {
    for (const { numerator, denominator, expected } of RENDERED) {
      expect(renderCanonicalAnswer(numerator, denominator)).toBe(expected);
    }
    expect(RENDERED.length).toBeGreaterThan(0);
  });

  it("everything it renders is already storage-canonical", () => {
    let checked = 0;
    for (const { numerator, denominator } of RENDERED) {
      const rendered = renderCanonicalAnswer(numerator, denominator);
      const stored = requireStoredCanonical(rendered);
      expect(stored, `requireStoredCanonical rejected ${rendered}`).toEqual({
        ok: true,
        value: rendered,
      });
      checked += 1;
    }
    expect(checked).toBe(RENDERED.length);
    // eslint-disable-next-line no-console
    console.log(`  render round-trip · ${checked} shapes`);
  });

  it("and the learner direction folds to the same string", () => {
    for (const { numerator, denominator } of RENDERED) {
      const rendered = renderCanonicalAnswer(numerator, denominator);
      expect(canonicalize(rendered)).toEqual({ ok: true, value: rendered });
    }
  });

  it("refuses a zero denominator rather than rendering nonsense", () => {
    expect(() => renderCanonicalAnswer(1n, 0n)).toThrow(/non-zero denominator/);
  });

  it("distinguishes an omitted denominator from a denominator of one", () => {
    expect(renderCanonicalAnswer(4n)).toBe("4");
    expect(renderCanonicalAnswer(4n, 1n)).toBe("4/1");
  });
});

/**
 * **The bug these cases exist to make unrepeatable (#50).** A whole answer of
 * `-9` was digested as `-9/1` while the shape beside it said `integer`, because
 * the shape and the spelling were computed separately. Every generated item in
 * the built pack was ungradeable, and the distractor-equals-answer guard —
 * which compares strings — stopped firing in the same stroke.
 *
 * **Two doors for the two inputs a caller can hold, and one decision behind
 * them**: `storedAnswer` from a `(numerator, denominator)` pair,
 * `storedAnswerOf` from a canonical spelling. Their agreement is swept over a
 * grid rather than over examples, because the three implementations this
 * replaced agreed on every example anybody had written down.
 *
 * **A fraction stays unreduced.** `canonicalize` does not fold `4/8` to `1/2`,
 * so a renderer that did would make the shipped pack's own answers ungradeable.
 *
 * **And `4/1` stays a fraction.** `storedAnswer` can never produce it —
 * `denominator === 1n` renders a whole number — so it is the one string where
 * the doors could have been made to disagree, and folding it would restate an
 * authored answer. Nothing refuses it, which is the half worth pinning: `4/1`
 * is #50's own string one sign away, and "the lifter was safe because
 * validation caught this" is a false reading of a real guard.
 *
 * **The refusal sweep runs over `CANON_INPUTS`** rather than over rows chosen
 * by hand, because a hand-chosen row is chosen by whoever already believes the
 * answer: the first draft asserted `2/4` was refused, and it is canonical. The
 * tag travels out unchanged, so a caller keeps what it already said, and both
 * arms are counted — a sweep that fell down one proves only that one (PROC-11).
 */
describe("a stored answer decides its shape and its spelling together", () => {
  it("a whole answer is whole, and says so", () => {
    expect(storedAnswer(-9n, 1n)).toEqual({ shape: "integer", canonical: "-9" });
    expect(storedAnswer(0n, 1n)).toEqual({ shape: "integer", canonical: "0" });
    expect(storedAnswer(42n, 1n)).toEqual({ shape: "integer", canonical: "42" });
  });

  it("and a fraction keeps its denominator, unreduced", () => {
    expect(storedAnswer(5n, 4n)).toEqual({ shape: "fraction", canonical: "5/4" });
    expect(storedAnswer(4n, 8n)).toEqual({ shape: "fraction", canonical: "4/8" });
    expect(storedAnswer(-3n, 2n)).toEqual({ shape: "fraction", canonical: "-3/2" });
  });

  it("and the two doors agree over a grid, whichever input a caller holds", () => {
    for (const numerator of [-9n, -3n, -1n, 0n, 1n, 4n, 5n, 42n]) {
      for (const denominator of [-2n, -1n, 1n, 2n, 4n, 5n, 7n, 12n]) {
        const fromPair = storedAnswer(numerator, denominator);
        const fromSpelling = storedAnswerOf(fromPair.canonical);
        expect(fromSpelling.ok, fromPair.canonical).toBe(true);
        expect(fromSpelling.ok && fromSpelling.value, `${numerator}/${denominator}`).toEqual(fromPair);
      }
    }
  });

  it("and a spelling a pack may state but the pair cannot produce keeps its denominator", () => {
    expect(requireStoredCanonical("4/1")).toEqual({ ok: true, value: "4/1" });
    expect(storedAnswerOf("4/1")).toEqual({ ok: true, value: { shape: "fraction", canonical: "4/1" } });
    expect(storedAnswer(4n, 1n)).toEqual({ shape: "integer", canonical: "4" });
  });

  it("and over the shared vector set it refuses exactly what storage refuses", () => {
    let accepted = 0;
    let refused = 0;
    for (const raw of CANON_INPUTS) {
      const stored = requireStoredCanonical(raw);
      const paired = storedAnswerOf(raw);
      if (!stored.ok) {
        refused += 1;
        expect(paired, JSON.stringify(raw)).toEqual({ ok: false, tag: stored.tag });
        continue;
      }
      accepted += 1;
      expect(paired, JSON.stringify(raw)).toEqual({
        ok: true,
        value: { shape: stored.value.includes("/") ? "fraction" : "integer", canonical: stored.value },
      });
    }
    expect(accepted).toBeGreaterThan(0);
    expect(refused).toBeGreaterThan(0);
    console.log(`  storedAnswerOf · ${accepted} accepted, ${refused} refused over CANON_INPUTS`);
  });

  it("and what it writes is what a keypad produces, which is what makes a digest reachable", () => {
    for (const [numerator, denominator] of [[-9n, 1n], [5n, 4n], [0n, 1n], [7n, 7n]] as const) {
      const stored = storedAnswer(numerator, denominator);
      const typed = canonicalize(stored.canonical);
      expect(typed.ok, stored.canonical).toBe(true);
      expect(typed.ok && typed.value).toBe(stored.canonical);
    }
  });
});
