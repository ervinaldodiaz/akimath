import type { Client } from "pg";

import { retentionCutoffs } from "../retention.js";

/**
 * Deletes what has expired, and reports what it deleted.
 *
 * The IO half: it reads the clock and runs the statements. Every figure comes
 * from `retention.ts`, which reads neither.
 *
 * **It must connect as `retention_job`.** That role is the only one holding
 * DELETE, and it holds it on every table a player leaves a row in, because
 * `ARCHITECTURE.md`:242 puts the erasure path `DELETE /v1/me` under the same
 * role. This job uses two of those grants; the endpoint will use the rest.
 *
 * Deleting attempts is safe because calibration never derives from raw rows —
 * `template_stats` is maintained on write. A test asserts those aggregates are
 * unchanged by a run, so a future path that starts deriving from raw rows
 * breaks a test rather than a player's history.
 */
export interface RetentionRun {
  readonly attempts: number;
  readonly diagEvents: number;
  readonly sessionDeltas: number;
  readonly offlinePacks: number;
  readonly issuedItems: number;
}

export async function runRetention(
  client: Client,
  now: Date,
): Promise<RetentionRun> {
  const cutoffs = retentionCutoffs(now);

  // Diagnosis events first: they reference attempts, and deleting the parent
  // first would cascade rows this job has not counted.
  const diagEvents = await client.query(
    "DELETE FROM diag_events WHERE created_at < $1",
    [cutoffs.diagEvents],
  );
  const attempts = await client.query(
    "DELETE FROM attempts WHERE created_at < $1",
    [cutoffs.attempts],
  );

  // **What each session did to the rating, on the attempts cutoff and not a
  // figure of its own.** A delta is an attribute of the history entry the
  // attempts above produce, so the two have to expire together: kept longer it
  // is a row nothing can reach, swept sooner it takes the figure off an entry
  // that is still being reported. One cutoff for both makes that difference
  // impossible to introduce.
  //
  // After the attempts delete, and guarded the same way as the two source
  // tables below: while any attempt of the session survives, the entry still
  // appears and it keeps its number.
  const sessionDeltas = await client.query(
    `DELETE FROM session_deltas
      WHERE created_at < $1
        AND NOT EXISTS (SELECT 1 FROM attempts
                         WHERE attempts.player_id = session_deltas.player_id
                           AND attempts.session_id = session_deltas.session_id)`,
    [cutoffs.attempts],
  );

  // **The two tables an attempt can point at, and they go last.** Both are
  // referenced with `ON DELETE CASCADE`, so sweeping either before the attempts
  // above would take answered history with it — the opposite of what a
  // retention job is for. `POST /packs` made this live: until something issued
  // a pack, `offline_packs` was empty and the gap was theoretical.
  //
  // **`NOT EXISTS` rather than trust in the arithmetic.** The cutoff is keyed
  // on the end of the usable window, so nothing referencing these rows should
  // have survived the deletes above — but "should" is what the cascade would
  // silently disprove, once, in production. The guard makes it structural: a
  // row with an attempt still on it is not deleted, whatever the dates say.
  const offlinePacks = await client.query(
    `DELETE FROM offline_packs
      WHERE expires_at < $1
        AND NOT EXISTS (SELECT 1 FROM attempts WHERE attempts.pack_id = offline_packs.id)`,
    [cutoffs.sources],
  );
  // Nothing writes `issued_items` yet — `GET /items/next` is still 501 — so
  // this sweeps an empty table today. It is here because the gap is the same
  // gap, and finding it the second time is not cheaper than finding it once.
  const issuedItems = await client.query(
    `DELETE FROM issued_items
      WHERE issued_at < $1
        AND NOT EXISTS (SELECT 1 FROM attempts WHERE attempts.issued_item_id = issued_items.id)`,
    [cutoffs.sources],
  );

  return {
    attempts: attempts.rowCount ?? 0,
    diagEvents: diagEvents.rowCount ?? 0,
    sessionDeltas: sessionDeltas.rowCount ?? 0,
    offlinePacks: offlinePacks.rowCount ?? 0,
    issuedItems: issuedItems.rowCount ?? 0,
  };
}
