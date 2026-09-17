import { z } from "zod";

import { KEYPAD_LAYOUTS } from "../keypad-layout.js";

/**
 * The request and response shapes the API serves.
 *
 * **Nothing here is invented.** `ItemResponse`, `AttemptSubmission` and `Verdict`
 * are transcribed from ADR 0001's spike, which carries them verbatim; the rest
 * are the endpoints `ARCHITECTURE.md` §5 names. Where a shape is genuinely
 * unstated it is an open question in `design.md`, because a specification is
 * expensive to change once a client is written against it and that is the whole
 * reason for freezing it early.
 *
 * Three invariants are visible in what is **absent**, and each has a test
 * sweeping the emitted document for it rather than trusting this comment:
 *
 * - No `templateId`, `templateVersion` or `seed`, anywhere. Those reconstruct
 *   the problem; `ARCHITECTURE.md` §4 is explicit that they never travel and
 *   that the client answers with the item id alone.
 * - No `options` on the item response. `ARCHITECTURE.md`:202 still lists it and
 *   §4's own resolution contradicts it — a field offering a player a set of
 *   answers to pick from is a different product. That line is corrected in this
 *   change.
 * - No correctness field on the submission. §4: the sync endpoint "does not
 *   accept an `ok` field — that is what makes the invariant true by construction
 *   rather than by discipline", and a schema is where by-construction lives.
 */

export const PromptTokenSchema = z.object({
  kind: z.enum(["number", "operator", "blank", "text"]),
  text: z.string(),
});

export const ItemResponseSchema = z.object({
  itemId: z.uuid(),
  prompt: z.array(PromptTokenSchema),
  keypad: z.enum(KEYPAD_LAYOUTS),
});

/** Which item in which pack. Identity for a pack item is `(packId, index)`. */
export const OfflinePackRefSchema = z.object({
  packId: z.uuid(),
  index: z.int().min(0),
});

/**
 * The longest an attempt may claim to have taken, in milliseconds — one hour.
 *
 * **A ceiling, because nothing else is one.** `attempts.elapsed_ms` is NOT NULL
 * and the figure is the client's: `issued_at → clientTs` measures wall-clock
 * latency, not time on task, and a pack item has no `issued_at` at all. Left
 * unbounded, one row saying somebody spent forty days on a subtraction reaches
 * `template_stats` and then calibration.
 *
 * **Refused above it, never clamped.** A clamped value is a lie that passes
 * every gate downstream of it.
 *
 * An hour is generous on purpose: a puzzle is allowed to be slow, and the app
 * shows no timer, so a player who puts the phone down mid-item is ordinary
 * rather than suspicious. The number is here and not in the server because this
 * is the frozen shape; `packages/server` holds it to the emitted `maximum`.
 */
export const ATTEMPT_ELAPSED_MS_MAX = 3_600_000;

/**
 * One answered item, on its way to sync.
 *
 * **It names exactly one source, and the schema cannot say so.**
 * `attempts_one_source` is `(issued_item_id) XOR (pack_id, pack_index)`, and
 * the wire mirrors it: `itemId` for an item the server issued, `packRef` for
 * one the player got in a pack. Both are optional here because a `oneOf` is a
 * union, `downconvert.ts` refuses one, and `ARCHITECTURE.md` §2 keeps the
 * surface flat for a hand-written Dart client. The rule is enforced where it
 * can be — the server's reader answers 400, and the database CHECK is behind
 * that — and stated in the operation's description so nobody has to guess.
 *
 * **Still no correctness field.** §4: the sync endpoint "does not accept an
 * `ok` field — that is what makes the invariant true by construction rather
 * than by discipline".
 */
export const AttemptSubmissionSchema = z.object({
  /** An item the server issued. Absent when `packRef` is present. */
  itemId: z.uuid().optional(),
  /** An item from a pack. Absent when `itemId` is present. */
  packRef: OfflinePackRefSchema.optional(),
  /**
   * The rating period. `ARCHITECTURE.md` §5 puts a client-generated session id
   * on every attempt; the frozen `attempts` table has no such column, so today
   * it groups the sync batch in flight and is not persisted. Where it should
   * live is an open question on `f1-core-rederivation`.
   */
  sessionId: z.uuid(),
  answer: z.string(),
  clientTs: z.iso.datetime(),
  /** Time on task. See [ATTEMPT_ELAPSED_MS_MAX] for why it is bounded. */
  elapsedMs: z.int().min(0).max(ATTEMPT_ELAPSED_MS_MAX),
});

/**
 * One graded attempt, echoing the source it graded.
 *
 * **The same two optionals as the submission, for the same reason.** A pack
 * attempt has no `itemId` — identity for a pack item is `(packId, index)` — so
 * a required one was a field the server could not fill for half the paths it
 * has to serve. Whichever the submission carried comes back on the verdict.
 *
 * Order is still the primary correlation: the operation returns one verdict per
 * attempt, in the order submitted. The echo is what lets a client check that
 * rather than trust it.
 */
export const VerdictSchema = z.object({
  /** Echoed from the submission. Absent when `packRef` is present. */
  itemId: z.uuid().optional(),
  /** Echoed from the submission. Absent when `itemId` is present. */
  packRef: OfflinePackRefSchema.optional(),
  ok: z.boolean(),
  /**
   * The diagnosis, opaque on the wire.
   *
   * `ARCHITECTURE.md` §2 forbids response polymorphism outright — no `oneOf`, no
   * `discriminator` — so variance lives inside an object, exactly as the frozen
   * pack format already types a stimulus payload.
   */
  payload: z.record(z.string(), z.unknown()),
});

export const AttemptBatchSchema = z.object({
  attempts: z.array(AttemptSubmissionSchema),
});

export const VerdictBatchSchema = z.object({
  verdicts: z.array(VerdictSchema),
});

export const OfflinePackSchema = z.object({
  packId: z.uuid(),
  issuedAt: z.iso.datetime(),
  expiresAt: z.iso.datetime(),
  /** The pack body, validated by the frozen pack schema rather than here. */
  pack: z.record(z.string(), z.unknown()),
});

/**
 * The three bands `players.age_band` accepts, declared once.
 *
 * **The band is a routing decision, not a demographic** (`CLAUDE.md`): it is
 * what sends a player into child protections or not. Two schemas below carry
 * it, and a set that drifted between them would let a request declare a band
 * the profile can never report back.
 */
const AGE_BANDS = ["under_13", "13_17", "adult"] as const;

/**
 * What a device sends to attach itself to an account.
 *
 * **The band travels with the link, and it has to.** `players.age_band` is NOT
 * NULL with no default, and ADR 0002 removed the guest sync that used to write
 * the row first — an unlinked device holds no session and leaves no row, so
 * this request *is* the row's creation. There is no later request at which the
 * band could arrive and no earlier one at which it could have.
 *
 * It is not read off the account either. Linking is an adult's act, but the
 * player being linked need not be an adult, and reading `adult` off the
 * credential would route a child out of their own protections — the one
 * mistake `age_band` exists to prevent.
 */
export const PlayerLinkSchema = z.object({
  playerId: z.uuid(),
  ageBand: z.enum(AGE_BANDS),
});

export const MeSchema = z.object({
  playerId: z.uuid(),
  ageBand: z.enum(AGE_BANDS),
  createdAt: z.iso.datetime(),
});

export const StandingSchema = z.object({
  playerId: z.uuid(),
  skills: z.array(
    z.object({
      skillId: z.int().min(1),
      rating: z.number(),
      deviation: z.number(),
      updatedAt: z.iso.datetime(),
    }),
  ),
});

export const HistoryEntrySchema = z.object({
  kind: z.enum(["series", "puzzle"]),
  title: z.string(),
  at: z.iso.datetime(),
  score: z.string(),
  /** Null for a puzzle, which carries no rating — drawn, not defensive. */
  ratingDelta: z.int().nullable(),
});

export const HistorySchema = z.object({
  entries: z.array(HistoryEntrySchema),
});

export const ErrorSchema = z.object({
  error: z.string(),
  message: z.string(),
});

/** Every named schema the document publishes, in emission order. */
export const API_SCHEMAS = {
  PromptToken: PromptTokenSchema,
  ItemResponse: ItemResponseSchema,
  AttemptSubmission: AttemptSubmissionSchema,
  AttemptBatch: AttemptBatchSchema,
  Verdict: VerdictSchema,
  VerdictBatch: VerdictBatchSchema,
  OfflinePackRef: OfflinePackRefSchema,
  OfflinePack: OfflinePackSchema,
  PlayerLink: PlayerLinkSchema,
  Me: MeSchema,
  Standing: StandingSchema,
  HistoryEntry: HistoryEntrySchema,
  History: HistorySchema,
  Error: ErrorSchema,
} as const;
