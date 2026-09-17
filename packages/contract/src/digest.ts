import { createHmac } from "node:crypto";

import { requireStoredCanonical, type CanonResult, type RejectionTag } from "./canon.js";

/**
 * The membership verifier `ARCHITECTURE.md` §4 asks for: the pack states a
 * digest, never the answer, so a player's device can tell right from wrong
 * offline without carrying the answer in readable bytes.
 *
 * Message construction is frozen here because it is a cross-stack contract
 * (`ARCHITECTURE.md` §1): the key is the pack's salt, the message is the UTF-8
 * bytes of the canonical answer and nothing else, the output is lowercase hex,
 * untruncated (design.md D4). `createHmac` reads no clock, no environment and
 * no entropy, so this stays on the pure side of PURE-1.
 */
export function answerDigest(packSaltHex: string, canonicalAnswer: string): string {
  return createHmac("sha256", Buffer.from(packSaltHex, "hex"))
    .update(canonicalAnswer, "utf8")
    .digest("hex");
}

export interface DigestProduced {
  readonly ok: true;
  readonly digest: string;
}

export interface DigestRefused {
  readonly ok: false;
  readonly tag: RejectionTag;
}

export type DigestResult = DigestProduced | DigestRefused;

/**
 * The only way pack content reaches a digest. Two spellings of one answer
 * would otherwise produce two digests and the player would be marked wrong for
 * a keystroke, so the stored answer has to be canonical already (design.md D5).
 */
export function digestStoredAnswer(packSaltHex: string, storedAnswer: string): DigestResult {
  const stored: CanonResult = requireStoredCanonical(storedAnswer);
  if (!stored.ok) {
    return { ok: false, tag: stored.tag };
  }
  return { ok: true, digest: answerDigest(packSaltHex, stored.value) };
}
