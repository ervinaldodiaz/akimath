import { requireStoredCanonical } from "./canon.js";
import { answerDigest } from "./digest.js";

/**
 * The digest parity table both stacks are measured against.
 *
 * **Emitted from the code, never hand-written** — `ARCHITECTURE.md` §3 records
 * what a hand-written golden cost the last time, when the canonical snippet
 * turned out not to produce the vector that was claimed.
 *
 * It exists *before* the second implementation does. `canon.golden.json` pins
 * how an answer is spelled and nothing pinned what it hashes to; that gap is
 * harmless while only this package computes a digest, and it becomes R2 the
 * moment the Flutter side does — which is what reading an issued pack offline
 * requires. Writing the fixture first is what makes the second implementation a
 * matter of passing a test rather than of reading a paragraph carefully.
 */

/**
 * The salt every vector is keyed on.
 *
 * **A published test salt, and it must be published**: a digest without the key
 * that produced it is a number nobody can reproduce. It is thirty-two bytes as
 * sixty-four hex characters, the shape a real `pack_salt` has, and it is chosen
 * so that decoding it matters — an implementation that keys on these characters
 * instead of the bytes they spell gets a plausible digest that matches nothing.
 */
export const DIGEST_GOLDEN_SALT =
  "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90";

/**
 * The answers to digest, as a learner's pack would carry them.
 *
 * Every one is put through `requireStoredCanonical` first, because that is the
 * only way pack content reaches a digest — two spellings of one answer would
 * otherwise produce two digests and a child would be marked wrong for a
 * keystroke.
 *
 * The set spans what a pack actually stores: whole numbers, a zero, both signs,
 * proper and improper fractions, and a fraction whose numerator is negative —
 * the shape a `-0/5` defect once slipped through on the canon side.
 */
export const DIGEST_INPUTS: readonly string[] = [
  "0",
  "7",
  "42",
  "-9",
  "1/2",
  "2/4",
  "1/3",
  "-1/2",
  "12/7",
  "100",
];

export interface DigestVector {
  /** The answer as a pack stores it, before canonicalizing. */
  readonly stored: string;
  /** What it canonicalizes to — the exact bytes that are hashed. */
  readonly canonical: string;
  /** Lowercase, untruncated hex. */
  readonly digest: string;
}

export interface DigestGolden {
  readonly pack_salt_hex: string;
  readonly vectors: readonly DigestVector[];
}

/**
 * The canonical spelling of a vector, or a throw.
 *
 * A vector the canonicalizer refuses is a vector nobody can digest, and a table
 * that silently dropped one would claim a coverage it does not have.
 */
function requireDigestibleSpelling(stored: string): string {
  const canonical = requireStoredCanonical(stored);
  if (!canonical.ok) {
    throw new Error(`"${stored}" is not a storable answer: ${canonical.tag}`);
  }
  return canonical.value;
}

export function buildDigestGolden(): DigestGolden {
  return {
    pack_salt_hex: DIGEST_GOLDEN_SALT,
    vectors: DIGEST_INPUTS.map((stored) => {
      const canonical = requireDigestibleSpelling(stored);
      return {
        stored,
        canonical,
        digest: answerDigest(DIGEST_GOLDEN_SALT, canonical),
      };
    }),
  };
}
