import { z } from "zod";

/**
 * What the keypad collects, and how the client decides whether the player was
 * right — without the pack ever stating the right answer.
 *
 * `ARCHITECTURE.md` §4: *"the answer never travels online. Offline, a
 * membership verifier travels."* The verifier is the digest: the client
 * canonicalizes what the player typed, digests it with the pack salt, and
 * compares. `shape` is the union the plan names — `(num, den)` for a fraction,
 * a single integer for series, matrix, analogy, hidden operation and figurate.
 */
export const ANSWER_SHAPES = ["integer", "fraction"] as const;

export type AnswerShape = (typeof ANSWER_SHAPES)[number];

/** Lowercase hex, untruncated SHA-256 — 64 characters (design.md D4). */
export const DigestSchema = z.string().regex(/^[0-9a-f]{64}$/u);

export const AnswerSpecSchema = z.strictObject({
  shape: z.enum(ANSWER_SHAPES),
  digest: DigestSchema,
});

export type AnswerSpec = z.infer<typeof AnswerSpecSchema>;
