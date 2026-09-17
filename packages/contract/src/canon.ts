import type { AnswerShape } from "./answer.js";

/**
 * Answer canonicalization — the one module both stacks must agree on
 * character for character. `ARCHITECTURE.md` §1 lists it as a cross-stack
 * contract; drift here makes a right answer wrong on one platform only.
 *
 * It runs in one direction and carries two obligations (design.md D5):
 * `canonicalize` folds what a keypad or a keyboard can legitimately produce,
 * and `requireStoredCanonical` refuses pack content that is not already
 * canonical, so two spellings of one answer can never produce two digests.
 */

/** Every way an answer can fail to be canonical. Closed on purpose. */
export type RejectionTag =
  | "empty"
  | "zero_denominator"
  | "non_numeric"
  | "non_ascii_digit"
  | "invisible_character"
  | "combining_mark"
  | "not_canonical";

export interface AnswerAccepted {
  readonly ok: true;
  readonly value: string;
}

export interface AnswerRejected {
  readonly ok: false;
  readonly tag: RejectionTag;
}

export type CanonResult = AnswerAccepted | AnswerRejected;

/**
 * The characters a learner can legitimately produce that mean an ASCII one.
 * U+2212 is the answer draft's `neg` key and the space is the placeholder an
 * empty field renders so the slot never collapses (plan §3.4).
 */
export const CHAR_MAP: Readonly<Record<string, string>> = Object.freeze({
  "−": "-",
  "⁄": "/",
  " ": "",
});

const INVISIBLE = /[\u00AD\u200B-\u200F\u2028\u2029\u2060\uFEFF]/u;
const COMBINING_MARK = /\p{M}/u;
const DECIMAL_DIGIT = /\p{Nd}/u;
const CANONICAL_SHAPE = /^(-?)(\d+)(?:\/(\d+))?$/u;

function hasNonAsciiDigit(raw: string): boolean {
  for (const character of raw) {
    if (DECIMAL_DIGIT.test(character) && !(character >= "0" && character <= "9")) {
      return true;
    }
  }
  return false;
}

function fold(raw: string): string {
  let folded = "";
  for (const character of raw) {
    folded += CHAR_MAP[character] ?? character;
  }
  return folded;
}

function stripLeadingZeros(digits: string): string {
  const stripped: string = digits.replace(/^0+/u, "");
  return stripped === "" ? "0" : stripped;
}

function joinCanonical(sign: string, numerator: string, denominator: string | undefined): string {
  const magnitude: string = stripLeadingZeros(numerator);
  const signed: string = magnitude === "0" ? magnitude : `${sign}${magnitude}`;
  return denominator === undefined ? signed : `${signed}/${stripLeadingZeros(denominator)}`;
}

function reject(tag: RejectionTag): AnswerRejected {
  return { ok: false, tag };
}

/**
 * Learner input in, the canonical answer out. Invisible characters and
 * combining marks are rejected rather than stripped: silently deleting a
 * character a player cannot see is how a wrong answer becomes a right one.
 */
export function canonicalize(raw: string): CanonResult {
  if (INVISIBLE.test(raw)) {
    return reject("invisible_character");
  }
  if (COMBINING_MARK.test(raw)) {
    return reject("combining_mark");
  }
  if (hasNonAsciiDigit(raw)) {
    return reject("non_ascii_digit");
  }

  const folded: string = fold(raw);
  if (folded === "") {
    return reject("empty");
  }

  const shape: RegExpExecArray | null = CANONICAL_SHAPE.exec(folded);
  if (shape === null) {
    return reject("non_numeric");
  }

  const [, sign = "", numerator = "", denominator] = shape;
  if (denominator !== undefined && stripLeadingZeros(denominator) === "0") {
    return reject("zero_denominator");
  }

  return { ok: true, value: joinCanonical(sign, numerator, denominator) };
}

/**
 * A canonical answer, built from the numbers rather than parsed from a string.
 *
 * **The inverse of `canonicalize`, and it calls the same private join.** That is
 * the whole design: rendering and canonicalising cannot disagree about what
 * `5/4` looks like, because there is one implementation of the spelling and both
 * directions go through it. Two canonicalisers already exist across two
 * languages and a differential fuzz over 22,440 inputs found 4,916 tag-only
 * divergences between them; a third copy — even "just a template literal" —
 * would reorder something and break a caller switching on the tag.
 *
 * It lives here and not in `packages/core` for the same reason: core has zero
 * dependencies and cannot import this module, so a renderer there would be a
 * second implementation by construction. Core produces exact values; this
 * decides how one is written down.
 *
 * **Omitting the denominator renders an integer; passing one always renders a
 * fraction, including `4/1`.** The shape is the caller's decision and the
 * spelling is this module's — `4/1` is canonical input to `canonicalize`, so it
 * has to be renderable, and guessing from the value would make `4/1` and `4`
 * the same call with different answers.
 */
export function renderCanonicalAnswer(
  numerator: bigint,
  denominator?: bigint,
): string {
  if (denominator === 0n) {
    throw new RangeError("a canonical answer needs a non-zero denominator");
  }

  const negative: boolean =
    numerator < 0n !== (denominator !== undefined && denominator < 0n);
  const magnitude = (value: bigint): string =>
    (value < 0n ? -value : value).toString();

  return joinCanonical(
    negative ? "-" : "",
    magnitude(numerator),
    denominator === undefined ? undefined : magnitude(denominator),
  );
}

/**
 * Pack content in, the same string out — or a rejection. A pack states its
 * answers already canonical, so nothing here folds: `not_canonical` is what a
 * stored spelling the learner direction *would* have folded earns, which is
 * what stops one answer from producing two digests (design.md D5).
 */
export function requireStoredCanonical(stored: string): CanonResult {
  const folded: CanonResult = canonicalize(stored);
  if (!folded.ok) {
    return folded;
  }
  return folded.value === stored ? folded : reject("not_canonical");
}

/**
 * How an exact answer is written down, shape and spelling together.
 *
 * **One decision, because two was a bug.** `packages/core`'s pack builder used
 * to compute `answer.shape` and the string the digest is taken over
 * separately, and the string always carried a denominator — so a whole answer
 * of −9 was digested as `-9/1` while the field beside it said `integer`, and
 * `canonicalize("-9")` is `-9`. Every generated item in the built pack was
 * ungradeable, and the guard that drops a distractor equal to the right answer
 * silently stopped firing, because it compares strings.
 *
 * **Two doors, one decision.** `storedAnswer` is for a caller holding an exact
 * `(numerator, denominator)` — `packages/core`'s template builder. `storedAnswerOf`
 * is for a caller holding a canonical *string* — `packages/core`'s authored-item
 * lifter, and `packages/server` grading a rederived item. Both compose the pair
 * below and neither lets a caller take half of it.
 *
 * The three callers are named because the gate that holds them to it can be
 * read: `packages/core/test/one-way-to-spell-an-answer.test.ts` and its sibling
 * in `packages/server`. They exist because for a while the sentence here said
 * "anything that turns a `(numerator, denominator)` into a stored answer calls
 * this" and named a consumer that did not exist, while two of the three real
 * ones made the decision by hand.
 */
export interface StoredAnswer {
  readonly shape: AnswerShape;
  /** Exactly what `canonicalize` returns for what a keypad can type. */
  readonly canonical: string;
}

export interface StoredAnswerRead {
  readonly ok: true;
  readonly value: StoredAnswer;
}

export type StoredAnswerResult = StoredAnswerRead | AnswerRejected;

/**
 * The decision itself: **an answer is a fraction exactly when it is written
 * with a denominator.**
 *
 * The shape is *derived from* the spelling rather than computed beside it,
 * which is the structural half of #50's fix. Computing them separately is what
 * let a whole answer of −9 be digested as `-9/1` under a field saying
 * `integer`; a shape that is a function of the string cannot come apart from
 * it however either door is called.
 *
 * **A search for the separator is exact here, not a heuristic.** Both callers
 * hand in a string this module has either rendered or validated, and
 * `CANONICAL_SHAPE` admits `/` in one position only — between the numerator and
 * the denominator. Re-running that regex to read its third group would buy
 * nothing and cost a null arm no input can reach: written that way, Stryker
 * survived the mutant that deletes the arm, and the arm folded "not canonical
 * at all" into "integer", which is the quiet-wrong this whole function exists
 * to remove.
 */
function storedAs(canonical: string): StoredAnswer {
  return { shape: canonical.includes("/") ? "fraction" : "integer", canonical };
}

export function storedAnswer(numerator: bigint, denominator: bigint): StoredAnswer {
  return storedAs(
    denominator === 1n
      ? renderCanonicalAnswer(numerator)
      : renderCanonicalAnswer(numerator, denominator),
  );
}

/**
 * The same decision for a caller who already holds the spelling — pack content,
 * or an answer read back off an artifact.
 *
 * **It validates rather than trusting**, so it is the safe composite all the
 * way through: `requireStoredCanonical` first, and its rejection tag travels
 * out unchanged, so a caller keeps whatever it already said about `not_canonical`
 * or `zero_denominator`. Handing back a `StoredAnswer` for a string that is not
 * storage-canonical would put a second sharp tool beside the safe one, which is
 * the shape of problem this function exists to remove.
 *
 * **`4/1` stays a fraction.** It is canonical input to `canonicalize`, so a pack
 * may state it, and folding it to an integer here would silently restate an
 * authored answer and move its digest. That is `renderCanonicalAnswer`'s stance
 * one level up — the shape is the content's decision and the spelling is this
 * module's. No authored answer is spelled that way today.
 */
export function storedAnswerOf(stored: string): StoredAnswerResult {
  const canonical: CanonResult = requireStoredCanonical(stored);
  return canonical.ok ? { ok: true, value: storedAs(canonical.value) } : canonical;
}
