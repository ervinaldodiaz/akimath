import type { TemplateRef } from "./template.js";

/**
 * What an issued pack recorded at each index, and how it is read back.
 *
 * **PURE**, and it exists because two packages had to agree about this shape
 * and neither owned it. `offline_packs.item_refs` is a `jsonb` array of these,
 * one per item and in the same order, which is what makes `(packId, index)`
 * address anything. Before this module the reader matched a comment in
 * `ARCHITECTURE.md` rather than a producer, and a mismatch would have surfaced
 * as every pack attempt 404ing.
 *
 * **Two kinds, because there are two ways to know an answer is right.**
 *
 * A **template** entry is rederived: the server regenerates the item from
 * `(template_id, template_version, seed, ladder_step)` and compares canonical
 * spellings. That is `ARCHITECTURE.md` §4's model and it works for anything a
 * template made.
 *
 * A **digest** entry is verified: the server computes
 * `HMAC(pack_salt, canonicalize(what was typed))` and compares it to what the
 * pack already carries. It exists because **authored content cannot be
 * rederived** — an authored item has no template reference, so `(packId,
 * index)` could not address it and nothing could grade it. Seventy of the
 * eighty items the app ships are authored, so without this the pack a player
 * actually plays could never be synced.
 *
 * **The server never learns an authored answer**, which is a stronger position
 * than the rederivation path leaves it in: it holds a digest and can only
 * confirm or deny a guess. `CLAUDE.md`'s invariant is that the answer never
 * travels *online*; for authored content it now never reaches the server at
 * all.
 *
 * **The seed is a string, and that is not a style choice.** `jsonb` is read
 * with `JSON.parse`, which loses a bigint above 2^53:
 * `1477776061723855037` comes back as `1477776061723855000`. Migration 0002
 * refuses a numeric seed inside the column for that reason, and this is the
 * code side of the same rule. Splitmix64 avalanches, so a seed off by one
 * rederives an unrelated item rather than a similar one.
 *
 * **snake_case**, matching the column and the pack format. A response shape is
 * camelCase and neither is renamed to match the other.
 */

/** An item a template made, addressed by what made it. */
export interface TemplateManifestEntry {
  readonly kind: "template";
  readonly template_id: string;
  readonly template_version: number;
  /** The `bigint` seed, decimal, as a string. Never a JSON number. */
  readonly seed: string;
  readonly ladder_step: number;
}

/** An item nobody can rederive, addressed by the digest of its answer. */
export interface DigestManifestEntry {
  readonly kind: "digest";
  /** 64 lowercase hex — `HMAC(pack_salt, canonical answer)`. */
  readonly digest: string;
  /**
   * Which skill it exercises.
   *
   * Carried, because `attempts.skill_id` is NOT NULL and there is no template
   * to ask. The pack's own item says so; this is that fact written down where
   * the server can reach it.
   */
  readonly skill_id: number;
}

export type ManifestEntry = TemplateManifestEntry | DigestManifestEntry;

/**
 * The digest's shape, re-derived rather than imported.
 *
 * `packages/contract`'s `DigestSchema` is the authority and this package may
 * not import it — `test/import_boundary.test.ts` holds the public surface to
 * importing no package at all. `test/template/manifest.test.ts` runs both over
 * the same probes, which is the arrangement this repository uses everywhere a
 * rule has to exist twice.
 */
const DIGEST = /^[0-9a-f]{64}$/u;

/** A template reference, written down. */
export function toManifestEntry(ref: TemplateRef): TemplateManifestEntry {
  return {
    kind: "template",
    template_id: ref.templateId,
    template_version: ref.templateVersion,
    seed: ref.seed.toString(),
    ladder_step: ref.ladderStep,
  };
}

/** An authored item, written down by the only thing that identifies it. */
export function toDigestEntry(item: {
  readonly digest: string;
  readonly skillId: number;
}): DigestManifestEntry {
  return { kind: "digest", digest: item.digest, skill_id: item.skillId };
}

/**
 * An entry read back, or null if it is not one.
 *
 * **Null rather than a throw.** The caller is a request handler holding a
 * manifest it did not write; a malformed entry is the server's problem, and
 * answering "no such item" is recoverable where a 500 for the whole batch is
 * not. A *reference the registry cannot resolve* is the other thing entirely
 * and does throw — see `resolve`.
 *
 * **`kind` is required.** Nothing has issued a pack in production, so there is
 * no kindless entry to be lenient about, and guessing from the fields present
 * is how a typo in `template_id` quietly becomes "this must be a digest".
 */
export function fromManifestEntry(value: unknown): ManifestEntry | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const entry = value as Record<string, unknown>;
  switch (entry["kind"]) {
    case "template":
      return _templateEntry(entry);
    case "digest":
      return _digestEntry(entry);
    default:
      return null;
  }
}

/**
 * A template entry read back, or null if the object is not one.
 *
 * **A numeric `seed` is refused rather than converted.** That is the bug
 * migration 0002 exists to prevent, and by the time the value reaches this
 * function it has already lost precision, so there is nothing left to recover:
 * a `string` is the only spelling that can be trusted.
 */
function _templateEntry(entry: Record<string, unknown>): TemplateManifestEntry | null {
  const { template_id, template_version, seed, ladder_step } = entry;
  if (
    typeof template_id !== "string" ||
    typeof template_version !== "number" ||
    !Number.isInteger(template_version) ||
    typeof seed !== "string" ||
    !/^-?\d+$/u.test(seed) ||
    typeof ladder_step !== "number" ||
    !Number.isInteger(ladder_step)
  ) {
    return null;
  }
  return {
    kind: "template",
    template_id,
    template_version,
    seed,
    ladder_step,
  };
}

function _digestEntry(entry: Record<string, unknown>): DigestManifestEntry | null {
  const { digest, skill_id } = entry;
  if (
    typeof digest !== "string" ||
    !DIGEST.test(digest) ||
    typeof skill_id !== "number" ||
    !Number.isInteger(skill_id) ||
    skill_id < 1
  ) {
    return null;
  }
  return { kind: "digest", digest, skill_id };
}

/**
 * The reference behind an entry, or null where there is not one.
 *
 * A digest entry has no reference and never will: that is the whole reason it
 * exists. Callers that rederive ask this; callers that grade ask the entry.
 */
export function templateRefOf(entry: ManifestEntry): TemplateRef | null {
  return entry.kind === "template"
    ? {
        templateId: entry.template_id,
        templateVersion: entry.template_version,
        seed: BigInt(entry.seed),
        ladderStep: entry.ladder_step,
      }
    : null;
}
