import type pg from "pg";
import { fromManifestEntry, templateRefOf, type ManifestEntry, type TemplateRef } from "@akimath/core";

import type { AttemptSource } from "../attempts.js";

/**
 * The queries `POST /attempts` needs.
 *
 * **ADAPTER.** SQL and the shape of a row; every decision about what an answer
 * *means* is `../attempts.ts`, which is pure.
 *
 * **Both source tables hand back a manifest entry, and `@akimath/core` decides
 * what it means.** `issued_items.seed` is `bigint`, OID 20, which
 * node-postgres returns as a raw string precisely because a JavaScript number
 * cannot hold it; `offline_packs.item_refs` is `jsonb`, parsed with
 * `JSON.parse`, so migration 0002 forbids a numeric seed inside it for the
 * same reason. So both arrive as `{template_id, template_version, seed,
 * ladder_step}` with the seed as text, and `fromManifestEntry` is the single
 * definition of how that is read — shared with the pack builder that will
 * write it, rather than matched against a comment.
 *
 * A malformed entry is answered as "no such item" rather than thrown: it is
 * the server's problem, and the alternative is a 500 for the whole batch over
 * one bad row in a pack nobody can fix from the client side.
 */

/**
 * The reference behind an issued item, or null if this player has no such item.
 *
 * **Scoped to the player, not just the id.** An item id is a uuid a caller
 * could have seen anywhere; without the `player_id` clause, one account could
 * record attempts against another's issued items.
 */
export async function refForIssuedItem(
  client: pg.ClientBase,
  playerId: string,
  itemId: string,
): Promise<TemplateRef | null> {
  const result = await client.query<{
    template_id: string;
    template_version: number;
    seed: string;
    ladder_step: number;
  }>(
    `SELECT template_id, template_version, seed::text AS seed, ladder_step
       FROM issued_items
      WHERE id = $1::uuid AND player_id = $2::uuid`,
    [itemId, playerId],
  );
  const row = result.rows[0];
  if (row === undefined) {
    return null;
  }
  // An issued item is always a template — that is what `issued_items` records —
  // so this is the one place the entry is expected to have a reference. A row
  // that somehow does not is answered as "no such item" rather than thrown.
  const entry = fromManifestEntry({ kind: "template", ...row });
  return entry === null ? null : templateRefOf(entry);
}

/**
 * What the pack recorded at that index, and the salt it was digested under.
 *
 * **An expired pack still grades.** `expires_at` governs whether a device may
 * keep *playing* a pack, and a phone that was offline for a fortnight is
 * carrying attempts that were legitimately earned. Refusing them here would
 * throw away a player's week because their sync was late.
 *
 * The index is read in SQL rather than by pulling the whole manifest across:
 * a fifty-item pack is one jsonb value, and a batch of fifty attempts against
 * it would otherwise fetch it fifty times.
 */
export interface PackItemSource {
  readonly entry: ManifestEntry;
  /** 32 lowercase hex. Needed to verify a digest entry and harmless otherwise. */
  readonly saltHex: string;
  /**
   * Which shipped content the pack copies, or null when it names none.
   *
   * **Carried because a digest entry records no difficulty.** A manifest entry
   * holds only the digest and the skill, so the item's `ladder_step` — which the
   * frozen pack schema requires on every item — is reachable only through the
   * content the row names. That step is the identity of the difficulty class the
   * rating measures, and every issuable pack today is a copy, so this is the
   * path that matters rather than the exception.
   */
  readonly contentId: string | null;
}

export async function entryForPackItem(
  client: pg.ClientBase,
  playerId: string,
  packId: string,
  index: number,
): Promise<PackItemSource | null> {
  const result = await client.query<{
    ref: unknown;
    salt_hex: string;
    content_id: string | null;
  }>(
    `SELECT item_refs -> $3::int         AS ref,
            encode(pack_salt, 'hex')     AS salt_hex,
            content_id
       FROM offline_packs
      WHERE id = $1::uuid AND player_id = $2::uuid`,
    [packId, playerId, index],
  );
  const row = result.rows[0];
  if (row === undefined) {
    return null;
  }
  const entry = fromManifestEntry(row.ref);
  return entry === null
    ? null
    : { entry, saltHex: row.salt_hex, contentId: row.content_id };
}

/** One graded attempt, ready for the table. */
export interface AttemptRow {
  readonly playerId: string;
  readonly source: AttemptSource;
  readonly sessionId: string;
  readonly skillId: number;
  readonly isCorrect: boolean;
  readonly elapsedMs: number;
  readonly answeredAt: string;
}

/**
 * Appends the batch, in one statement.
 *
 * **`gen_random_uuid()` rather than an id from here.** `attempts.id` has no
 * default and no caller ever names it, so minting it in SQL keeps the one
 * source of randomness in the database and out of a module that would then
 * need a generator injected to stay testable.
 *
 * **One statement, not one per row.** A batch is already inside a transaction,
 * so correctness does not depend on it; two hundred round trips instead of one
 * does.
 *
 * **`ON CONFLICT DO NOTHING`, over migration 0004's two partial unique
 * indexes.** A client whose sync timed out and resent the batch would
 * otherwise double every row it carried, on a table that accepts no UPDATE and
 * no DELETE from the request path — nothing could clean it up, and the counts
 * would stay wrong. The verdicts are recomputed from the same inputs, so the
 * second answer is the first one: idempotent by nature rather than by a replay
 * store, the same way `linkPlayer` is.
 *
 * It also absorbs a duplicate *within* one statement, which Postgres allows for
 * `DO NOTHING` — but `readAttemptBatch` refuses that case first, because
 * keeping one of two rows and answering as if both landed is worse than saying
 * so.
 *
 * **It answers with the rows that landed, and that is what the rating reads.**
 * A resent batch inserts nothing, so a caller rating what it *submitted* would
 * move a player's rating twice for one answer — and `attempts` accepts no
 * UPDATE and no DELETE from the request path, so nothing could undo it. A count
 * is not enough either: a batch is routinely part new and part replay, and the
 * rating has to know *which* rows are new. `RETURNING` is the only thing that
 * can say, because `ON CONFLICT DO NOTHING` omits the conflicting rows from it.
 */
export async function insertAttempts(
  client: pg.ClientBase,
  rows: readonly AttemptRow[],
): Promise<readonly AttemptSource[]> {
  if (rows.length === 0) {
    return [];
  }
  const PER_ROW = 8;
  const values: unknown[] = [];
  const tuples = rows.map((row, position) => {
    const at = position * PER_ROW;
    values.push(
      row.playerId,
      row.source.kind === "issued" ? row.source.itemId : null,
      row.source.kind === "pack" ? row.source.packId : null,
      row.source.kind === "pack" ? row.source.index : null,
      row.skillId,
      row.isCorrect,
      row.elapsedMs,
      row.sessionId,
    );
    return (
      `(gen_random_uuid(), $${at + 1}::uuid, $${at + 2}::uuid, $${at + 3}::uuid, ` +
      `$${at + 4}::smallint, $${at + 5}::smallint, $${at + 6}::boolean, ` +
      `$${at + 7}::integer, $${at + 8}::uuid, ` +
      // The timestamps go last, all together, so a row's own parameters stay a
      // contiguous run and the arithmetic above has one stride rather than two.
      `$${rows.length * PER_ROW + position + 1}::timestamptz)`
    );
  });
  values.push(...rows.map((row) => row.answeredAt));

  const result = await client.query<{
    issued_item_id: string | null;
    pack_id: string | null;
    pack_index: number | null;
  }>(
    `INSERT INTO attempts
       (id, player_id, issued_item_id, pack_id, pack_index, skill_id, is_correct,
        elapsed_ms, session_id, answered_at)
     VALUES ${tuples.join(", ")}
     ON CONFLICT DO NOTHING
     RETURNING issued_item_id, pack_id, pack_index`,
    values,
  );
  return result.rows.map(landedSource);
}

/**
 * Which item a returned row is about.
 *
 * The columns mirror `attempts_one_source`, so exactly one of the two arms is
 * populated — reading `issued_item_id` first is not a preference between them,
 * it is the check the constraint already guarantees the answer to.
 */
function landedSource(row: {
  readonly issued_item_id: string | null;
  readonly pack_id: string | null;
  readonly pack_index: number | null;
}): AttemptSource {
  if (row.issued_item_id !== null) {
    return { kind: "issued", itemId: row.issued_item_id };
  }
  if (row.pack_id === null || row.pack_index === null) {
    // Unreachable while `attempts_one_source` is on the table, and thrown
    // rather than guessed: a row naming no item cannot be rated, and silently
    // dropping it would make the rating quietly incomplete.
    throw new Error("an attempt row names no source, which the constraint forbids");
  }
  return { kind: "pack", packId: row.pack_id, index: row.pack_index };
}
