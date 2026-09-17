import { answerDigest, storedAnswerOf, type Item } from "@akimath/contract";

/**
 * An authored item, lifted into the frozen envelope.
 *
 * **PURE** — a decoded value in, an `Item` out. Reading the file is the CLI's.
 *
 * **An envelope problem, not a content problem.** A spike ran all seventy
 * authored items through `parsePack` and every one was accepted with its
 * content untouched; only `skill_id`, `keypad`, the digest answer and
 * `diagnosis` had to be added. That is why this module adds fields and
 * translates one shape, and does nothing else: a payload rewritten here would
 * mean two places decide what a matrix is.
 *
 * The one translation is arithmetic. The app spells an expression as the token
 * list its compositor draws; the frozen payload spells it structurally as
 * `{left, operator, right}`. All twenty authored expressions are exactly
 * `term operator term =`, so the translation is total rather than best-effort —
 * and anything that is not that shape is refused rather than approximated.
 */

export interface LiftOptions {
  readonly skillId: number;
  readonly packSalt: string;
}

/** The authored file, as a list of items. Parsing only — no lifting. */
export function readAuthoredFile(text: string): readonly unknown[] {
  const parsed: unknown = JSON.parse(text);
  if (typeof parsed !== "object" || parsed === null) {
    throw new TypeError("authored file: not an object");
  }
  const items = (parsed as { items?: unknown }).items;
  if (!Array.isArray(items) || items.length === 0) {
    throw new TypeError("authored file: items must be a non-empty array");
  }
  return items;
}

/**
 * The glyph the app draws, and the one the contract froze.
 *
 * They differ for subtraction: the app uses U+2212 MINUS SIGN, which is the
 * correct typographic mark, and `ARITHMETIC_OPERATORS` froze the ASCII hyphen.
 * `stimulus_reader.dart` translates the other way for the same reason; the two
 * are a pair and neither is complete alone.
 *
 * **U+002D is deliberately not a key.** This is a table of marks, and the
 * hyphen is a name — the contract's name for subtraction, which is why it
 * appears on the right. Accepting it on the left as well was tolerance the
 * app does not share: `arithmetic_glyphs.dart` refuses it, so a build that
 * took it would emit a pack from an authored file the app cannot read, which
 * is the same format admitting different content at each of its two doors.
 */
const OPERATORS: Readonly<Record<string, string>> = {
  "+": "+",
  "−": "-",
  "×": "×",
  "÷": "÷",
};

interface Term {
  readonly num: number;
  readonly den: number;
}

function termOf(token: unknown, id: string): Term {
  const t = token as { kind?: string; value?: string; numerator?: string; denominator?: string };
  if (t.kind === "text" && t.value !== undefined) {
    return { num: Number(t.value), den: 1 };
  }
  if (t.kind === "fraction" && t.numerator !== undefined && t.denominator !== undefined) {
    return { num: Number(t.numerator), den: Number(t.denominator) };
  }
  throw new TypeError(`item "${id}": a term must be text or a fraction`);
}

/**
 * An authored expression, as the frozen arithmetic payload spells it.
 *
 * **`term operator term =` and nothing else.** A longer expression is a shape
 * the frozen payload cannot hold, and silently dropping the tail would ship a
 * different question than the one that was authored.
 */
function arithmeticFrom(prompt: readonly unknown[], id: string): unknown {
  if (prompt.length !== 4) {
    throw new TypeError(
      `item "${id}": an expression must be term, operator, term, equals — got ${prompt.length} tokens`,
    );
  }
  const glyph = (prompt[1] as { glyph?: string }).glyph ?? "";
  const operator = OPERATORS[glyph];
  if (operator === undefined) {
    throw new TypeError(`item "${id}": "${glyph}" is not one of the four operators the contract froze`);
  }
  return {
    kind: "arithmetic",
    payload: { operator, left: termOf(prompt[0], id), right: termOf(prompt[2], id) },
  };
}

/**
 * One authored item, in the frozen envelope.
 *
 * **Shape and spelling come from the one decision, `storedAnswerOf`.** This
 * read the raw field for a `/` instead — a second implementation of
 * `storedAnswer`, agreeing by coincidence, which is the state #50 shipped
 * from. The decision lives in `packages/contract` so the pack builder and the
 * server make one choice about both halves, and the shape is *derived from*
 * the spelling rather than computed beside it, which is what stops them coming
 * apart again. `storedAnswerOf` states there why `4/1` stays a fraction, and
 * that no authored answer is spelled that way today. Held by
 * `test/one-way-to-spell-an-answer.test.ts`.
 *
 * **Content is validated where it is read**, and `storedAnswerOf` validates,
 * so the refusal is unchanged by the move. A digest over a non-canonical
 * answer grades a right answer wrong, on a device, with nothing reporting an
 * error — which is exactly what the app's own reader refuses too.
 *
 * `keypad` is `item`, the only layout an item ever uses; `puzzle` and `otp`
 * belong to other surfaces. Not a declaration choice, so not in the
 * declaration.
 *
 * `diagnosis` is authored content, filled in by the diagnosis pass. Nullable
 * in the frozen format precisely so the copy is not a prerequisite for a valid
 * pack.
 */
export function liftAuthored(authored: unknown, options: LiftOptions): Item {
  const raw = authored as {
    id?: string;
    ladder_step?: number;
    answer?: string;
    prompt?: readonly unknown[];
    stimulus?: unknown;
  };
  const id = raw.id ?? "<unnamed>";

  if (raw.prompt !== undefined && raw.stimulus !== undefined) {
    throw new TypeError(`item "${id}": carries both a prompt and a stimulus; it asks one question`);
  }
  const stimulus =
    raw.stimulus !== undefined
      ? raw.stimulus
      : arithmeticFrom(raw.prompt ?? [], id);

  const answer = raw.answer ?? "";
  const stored = storedAnswerOf(answer);
  if (!stored.ok) {
    throw new TypeError(`item "${id}": answer "${answer}" is not storage-canonical (${stored.tag})`);
  }

  return {
    skill_id: options.skillId,
    ladder_step: raw.ladder_step as number,
    keypad: "item",
    stimulus: stimulus as Item["stimulus"],
    answer: {
      shape: stored.value.shape,
      digest: answerDigest(options.packSalt, stored.value.canonical),
    },
    diagnosis: null,
  };
}
