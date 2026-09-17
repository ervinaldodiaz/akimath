import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { answerDigest, ItemSchema } from "@akimath/contract";
import { describe, expect, it } from "vitest";

import { liftAuthored, readAuthoredFile } from "../../src/pack/lift.js";
import { AUTHORED_PACK_PATH } from "../authored-pack.js";

/**
 * The lift turns the app's authored content into the frozen envelope.
 *
 * Two hazards run through the whole file. A digest assertion has to be about
 * *this* answer rather than about a well-shaped string — the falsification pass
 * found that hashing a constant satisfied a `/^[0-9a-f]{64}$/` assertion, which
 * is every property except the one a digest exists for. And a value the lift is
 * handed everywhere else, `skillId` 1 most of all, has to be varied in at least
 * one case, or hardcoding it passes the whole suite.
 */

const SALT = "a1b2c3d4e5f60718293a4b5c6d7e8f90";
const lift = (item: unknown) => liftAuthored(item, { skillId: 1, packSalt: SALT });

/** The arithmetic payload of a lifted item, for the assertions that read into it. */
const payloadOf = (item: unknown): Record<string, unknown> =>
  (item as { stimulus: { payload: Record<string, unknown> } }).stimulus.payload;

/** The file the app actually ships. Read, not copied — see the group below. */
const AUTHORED = AUTHORED_PACK_PATH;

/**
 * The app spells an expression as a token list because that is what its
 * compositor draws; the frozen payload spells it structurally. All twenty
 * authored items are exactly `term operator term =`, so the translation is
 * total rather than best-effort.
 *
 * **The minus sign is two marks, and only one of them is authored content.**
 * The app draws U+2212, which is the correct typographic mark, and the frozen
 * operator set is the ASCII hyphen; the Dart reader translates the other way,
 * and this group is its counterpart. No fixture exercises subtraction, so
 * without it the pair could drift. The hyphen itself is refused, where this
 * used to accept both spellings and map them to the frozen `-`: an authored
 * prompt carries the glyph it draws, and the hyphen is the contract's *name*
 * for subtraction rather than the mark. Accepting it would let
 * `npm run build:pack` succeed on a file the app cannot read — the same format,
 * two doors, disagreeing about what may go through.
 */
describe("an authored arithmetic item becomes a frozen envelope", () => {
  const authored = {
    id: "a1",
    ladder_step: 3,
    answer: "5/4",
    prompt: [
      { kind: "fraction", numerator: "3", denominator: "4" },
      { kind: "operator", glyph: "+" },
      { kind: "fraction", numerator: "2", denominator: "4" },
      { kind: "operator", glyph: "=" },
    ],
  };

  it("becomes left, operator and right", () => {
    expect(lift(authored).stimulus).toEqual({
      kind: "arithmetic",
      payload: {
        operator: "+",
        left: { num: 3, den: 4 },
        right: { num: 2, den: 4 },
      },
    });
  });

  it("writes a whole number as a denominator of one", () => {
    const whole = { ...authored, answer: "13", prompt: [
      { kind: "text", value: "7" },
      { kind: "operator", glyph: "+" },
      { kind: "text", value: "6" },
      { kind: "operator", glyph: "=" },
    ] };
    expect(payloadOf(lift(whole))).toMatchObject({
      left: { num: 7, den: 1 },
      right: { num: 6, den: 1 },
    });
  });

  it("translates the minus sign the app draws into the one the contract froze", () => {
    const minus = { ...authored, answer: "1", prompt: [
      { kind: "text", value: "9" },
      { kind: "operator", glyph: "−" },
      { kind: "text", value: "8" },
      { kind: "operator", glyph: "=" },
    ] };
    expect(payloadOf(lift(minus))["operator"]).toBe("-");
  });

  it("refuses the ASCII hyphen, which is a name and not a mark", () => {
    const item = { ...authored, answer: "1", prompt: [
      { kind: "text", value: "9" },
      { kind: "operator", glyph: "-" },
      { kind: "text", value: "8" },
      { kind: "operator", glyph: "=" },
    ] };
    expect(() => lift(item)).toThrow(TypeError);
  });

  it("carries the answer as a digest of its own value, never in the clear", () => {
    const item = lift(authored);
    expect(item.answer.shape).toBe("fraction");
    expect(item.answer.digest).toBe(answerDigest(SALT, "5/4"));
    expect(JSON.stringify(item)).not.toContain("5/4");
  });

  it("gives two different answers two different digests", () => {
    const other = lift({ ...authored, answer: "7/4" });
    expect(other.answer.digest).not.toBe(lift(authored).answer.digest);
  });

  it("gives one answer different digests under different salts, ruling out a lookup table", () => {
    const elsewhere = liftAuthored(authored, {
      skillId: 1,
      packSalt: "00112233445566778899aabbccddeeff",
    });
    expect(elsewhere.answer.digest).not.toBe(lift(authored).answer.digest);
  });

  it("adds the envelope fields and nothing else", () => {
    expect(liftAuthored(authored, { skillId: 7, packSalt: SALT }).skill_id).toBe(7);
    const item = lift(authored);
    expect(item.skill_id).toBe(1);
    expect(item.ladder_step).toBe(3);
    expect(item.keypad).toBe("item");
    expect(item.diagnosis).toBeNull();
    expect(Object.keys(item).sort()).toEqual([
      "answer", "diagnosis", "keypad", "ladder_step", "skill_id", "stimulus",
    ]);
  });
});

/**
 * A non-arithmetic stimulus passes through untouched.
 *
 * The lift is an envelope problem. Touching one of these payloads here would
 * mean two places decide what a matrix is.
 */
describe("a non-arithmetic stimulus passes through untouched", () => {
  const kinds = [
    ["numberSeries", { terms: [2, 4, 8, 16, 32], unknown_index: 4 }],
    ["matrix", { size: 3, cells: [1, 2, 3, 2, 4, 6, 3, 6, 9], unknown_index: 8 }],
    ["analogy", { pairs: [{ left: 2, right: 4 }, { left: 5, right: 10 }], unknown_index: 3 }],
    ["hiddenOperation", { examples: [{ input: 2, output: 7 }, { input: 5, output: 16 }], query_input: 9 }],
    ["figurate", { figures: [{ dots: 1 }, { dots: 3 }, { dots: 6 }], unknown_index: 2 }],
  ] as const;

  for (const [kind, payload] of kinds) {
    it(`${kind} is byte-identical after lifting`, () => {
      const stimulus = { kind, payload };
      const item = lift({ id: kind, ladder_step: 2, answer: "7", stimulus });

      expect(item.stimulus).toEqual(stimulus);
      expect(ItemSchema.safeParse(item).success).toBe(true);
    });
  }
});

/**
 * Refused where it is read, because every alternative is silent. A digest taken
 * over an answer that is not storage-canonical grades a right answer wrong, on
 * a device, with nothing reporting an error.
 */
describe("content the frozen format cannot accept fails where it is read", () => {
  it("refuses an answer that is not storage-canonical", () => {
    expect(() => lift({ id: "bad", ladder_step: 1, answer: " 007 ", stimulus: {
      kind: "numberSeries", payload: { terms: [1, 2, 3], unknown_index: 0 },
    } })).toThrow(/bad/);
  });

  it("refuses an item carrying both a prompt and a stimulus", () => {
    expect(() => lift({
      id: "both", ladder_step: 1, answer: "1",
      prompt: [{ kind: "text", value: "1" }],
      stimulus: { kind: "numberSeries", payload: { terms: [1, 2, 3], unknown_index: 0 } },
    })).toThrow(/both/);
  });

  it("refuses an expression that is not term operator term", () => {
    expect(() => lift({ id: "long", ladder_step: 1, answer: "1", prompt: [
      { kind: "text", value: "1" },
      { kind: "operator", glyph: "+" },
      { kind: "text", value: "2" },
      { kind: "operator", glyph: "+" },
      { kind: "text", value: "3" },
      { kind: "operator", glyph: "=" },
    ] })).toThrow(/long/);
  });

  it("refuses an operator the frozen set does not name", () => {
    expect(() => lift({ id: "op", ladder_step: 1, answer: "1", prompt: [
      { kind: "text", value: "1" },
      { kind: "operator", glyph: "^" },
      { kind: "text", value: "2" },
      { kind: "operator", glyph: "=" },
    ] })).toThrow(/op/);
  });
});

/**
 * The whole shipped authored file lifts.
 *
 * **Read, not copied.** A fixture copy would let the app's real content drift
 * from what this proves liftable, and the drift would surface as a pack that no
 * longer matches the game. This is the assertion that keeps one source of truth
 * while two formats coexist.
 */
describe("the whole shipped authored file lifts", () => {
  const items = readAuthoredFile(readFileSync(AUTHORED, "utf8"));

  it("every item is accepted by the frozen item schema", () => {
    const lifted = items.map((item) => liftAuthored(item, { skillId: 1, packSalt: SALT }));
    const bad = lifted
      .map((item, index) => ({ index, parsed: ItemSchema.safeParse(item) }))
      .flatMap(({ index, parsed }) =>
        parsed.success ? [] : [`item ${index}: ${parsed.error.issues[0]?.message ?? ""}`],
      );

    expect(bad).toEqual([]);
    expect(lifted.length).toBeGreaterThan(0);
  });

  it("covers every stimulus family, reporting a breakdown a silent drop cannot pass", () => {
    const byKind = new Map<string, number>();
    for (const item of items) {
      const kind = (item as { stimulus?: { kind: string } }).stimulus?.kind ?? "arithmetic";
      byKind.set(kind, (byKind.get(kind) ?? 0) + 1);
    }
    // eslint-disable-next-line no-console
    console.log(
      `  authored lift · ${items.length} items → ` +
        [...byKind.entries()].map(([k, n]) => `${k} ${n}`).join(", "),
    );
    expect(byKind.size).toBe(6);
    expect(items.length).toBe(70);
  });
});
