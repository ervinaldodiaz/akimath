import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { runRetention } from "../src/adapters/retention-job.js";
import { retentionCutoffs, RETENTION_DAYS } from "../src/retention.js";
import {
  describeWithDatabase,
  freshDatabase,
  type TestDatabase,
} from "./support/database.js";

const DAY_MS = 24 * 60 * 60 * 1000;

describe("the cutoffs are computed from an injected instant", () => {
  it("attempts expire after 400 days, diagnosis events after 30, sources after 400", () => {
    const now = new Date("2026-08-17T09:00:00.000Z");
    const cutoffs = retentionCutoffs(now);

    expect(cutoffs.attempts.toISOString()).toBe(
      new Date(now.getTime() - 400 * DAY_MS).toISOString(),
    );
    expect(cutoffs.diagEvents.toISOString()).toBe(
      new Date(now.getTime() - 30 * DAY_MS).toISOString(),
    );
    // Spelled out rather than compared to `cutoffs.attempts`: the two are the
    // same number today and are not the same *decision*, and an assertion that
    // said "equal to attempts" would pass for any value of either.
    expect(cutoffs.sources.toISOString()).toBe(
      new Date(now.getTime() - 400 * DAY_MS).toISOString(),
    );
  });

  it("and a source is never swept before the attempts that reference it", () => {
    // The invariant behind the figure, not the figure. `attempts.pack_id` and
    // `attempts.issued_item_id` both cascade, so a source cutoff more recent
    // than the attempts one would delete answered history.
    const cutoffs = retentionCutoffs(new Date("2026-08-17T09:00:00.000Z"));
    expect(cutoffs.sources.getTime()).toBeLessThanOrEqual(cutoffs.attempts.getTime());
  });

  it("the two figures are not the same figure", () => {
    // PROC-11: a test that only checks "some cutoff came back" passes for a
    // module returning `now` twice.
    const cutoffs = retentionCutoffs(new Date("2026-08-17T09:00:00.000Z"));
    expect(cutoffs.attempts.getTime()).toBeLessThan(
      cutoffs.diagEvents.getTime(),
    );
  });

  it("it reads no clock — the same instant always gives the same answer", () => {
    const now = new Date("2026-08-17T09:00:00.000Z");
    expect(retentionCutoffs(now)).toEqual(retentionCutoffs(now));
  });
});

describe("a cutoff is absolute elapsed time, not a walk over local midnights", () => {
  it("400 days spanning a daylight-saving transition is still 400 x 24 h", () => {
    // **The Dart side already paid for the other reading.** `StreakPolicy`
    // walked back with `subtract(Duration(days: 1))` over local midnights and
    // lost a player's whole 30-day streak across a Tijuana transition. Here the
    // calendar reading would be the bug: retention is a policy about elapsed
    // time, and 400 days must not become 399 or 401 because a clock moved.
    //
    // Run under `TZ=America/Tijuana` as well as UTC — CI runs UTC, so a
    // zone-dependent bug is invisible unless the zone is named.
    const now = new Date("2026-03-09T15:00:00.000Z"); // the day after a US transition
    const cutoff = retentionCutoffs(now).attempts;

    expect(now.getTime() - cutoff.getTime()).toBe(400 * DAY_MS);
  });

  it("the same holds for the 30-day figure", () => {
    const now = new Date("2026-11-02T15:00:00.000Z"); // the day after the other one
    const cutoff = retentionCutoffs(now).diagEvents;

    expect(now.getTime() - cutoff.getTime()).toBe(30 * DAY_MS);
  });
});

describe("the figures live in exactly one module", () => {
  /** Every `.ts` under `src/`, so a mistyped glob cannot pass vacuously. */
  function sourceFiles(directory: string): string[] {
    return readdirSync(directory).flatMap((entry) => {
      const full = path.join(directory, entry);
      if (statSync(full).isDirectory()) {
        return sourceFiles(full);
      }
      return full.endsWith(".ts") ? [full] : [];
    });
  }

  // **Skipped when the tree is instrumented, on purpose.** This is a gate on
  // the shape of the source, not on behaviour, and Stryker runs the suite
  // against a rewritten copy of `src/` in a sandbox — every file it touches
  // gains numeric mutant ids, so a bare-number search finds them and reports a
  // duplication that exists only inside the mutation run.
  //
  // **Decided from the files, not from an environment variable.** It used to
  // read `STRYKER_MUTATOR_RUNNER`, which is not set during the *dry* run — so
  // the gate did run against the instrumented tree, and passed only because no
  // rewritten file happened to contain a bare `400`. Adding a source file
  // shifted the ids, one landed on 400, and the whole mutation run aborted on a
  // failure that had nothing to do with retention. Asking whether the bytes
  // carry Stryker's marker cannot go stale that way.
  const marker = "stry" + "MutAct_";
  const allSources = sourceFiles(fileURLToPath(new URL("../src", import.meta.url)));
  const instrumented = allSources.some((file) => readFileSync(file, "utf8").includes(marker));

  /// Files where `400` is an HTTP status and not a number of days.
  ///
  /// **Named, with the reason, rather than loosening the pattern.** The sweep
  /// below protects one thing: that nobody restates the retention period
  /// instead of importing `RETENTION_DAYS`. `400` acquired a second meaning the
  /// day `linkPlayer` landed and the router learned to answer `400 Bad
  /// Request`, and a pattern relaxed to accommodate that would stop catching
  /// the duplication it exists for.
  ///
  /// An entry here is a promise that the file has nothing to do with retention.
  const HTTP_STATUS_FILES: readonly string[] = ["link.ts", "http-server.ts", "attempts.ts"];

  it.skipIf(instrumented)("every excused file is excused for a reason", () => {
    // A file that no longer exists would silently excuse nothing.
    const src = fileURLToPath(new URL("../src", import.meta.url));
    for (const excused of HTTP_STATUS_FILES) {
      const found = sourceFiles(src).filter((file) => path.basename(file) === excused);
      expect(found, `${excused} is excused and absent`).toHaveLength(1);
      // And it really is an HTTP file, not one quietly holding a day count.
      //
      // `retention_job` is struck out first: it is the name of a database role,
      // not a figure. The erasure path runs under it by invariant, so
      // `http-server.ts` has to be able to say the word — and a gate that
      // forbids naming the role you use gets deleted rather than obeyed. What
      // is left of the pattern still catches a window or a day count.
      const withoutTheRoleName = readFileSync(found[0]!, "utf8").replaceAll("retention_job", "");
      expect(withoutTheRoleName).not.toMatch(/RETENTION|days/i);
    }
  });

  it.skipIf(instrumented)("400 appears in retention.ts and nowhere else in src/", () => {
    const src = fileURLToPath(new URL("../src", import.meta.url));
    const files = sourceFiles(src);

    // PROC-10: report what was scanned, and scanning nothing is a failure.
    expect(files.length).toBeGreaterThan(0);
    console.log(`  retention figures · scanned ${files.length} source files`);

    const offenders = files.filter((file) => {
      if (path.basename(file) === "retention.ts") {
        return false;
      }
      if (HTTP_STATUS_FILES.includes(path.basename(file))) {
        return false;
      }
      const contents = readFileSync(file, "utf8");
      // `400` only. `30` is a number ordinary code may legitimately hold, and a
      // gate that forbids it everywhere is a gate someone disables; the 30 is
      // protected by living in the same literal as the 400.
      return /\b400\b/.test(contents);
    });

    expect(
      offenders.map((file) => path.relative(src, file)),
      "the retention figures are duplicated outside retention.ts",
    ).toEqual([]);
  });

  it.skipIf(instrumented)("RETENTION_DAYS is declared in exactly one file", () => {
    const src = fileURLToPath(new URL("../src", import.meta.url));
    const declaring = sourceFiles(src).filter((file) =>
      /export const RETENTION_DAYS/.test(readFileSync(file, "utf8")),
    );

    expect(declaring.map((file) => path.basename(file))).toEqual([
      "retention.ts",
    ]);
  });

  it("the constant is what the function uses, not a second copy", () => {
    // Exported so the adapter and the SQL can name it rather than restating it.
    const now = new Date("2026-08-17T09:00:00.000Z");
    expect(RETENTION_DAYS.attempts).toBe(400);
    expect(RETENTION_DAYS.diagEvents).toBe(30);
    expect(now.getTime() - retentionCutoffs(now).attempts.getTime()).toBe(
      RETENTION_DAYS.attempts * DAY_MS,
    );
  });
});

describeWithDatabase("the job, against a real database", () => {
  const PLAYER = "018f4e3c-0000-7000-8000-0000000000f1";
  let db: TestDatabase;

  /**
   * An attempt aged by `days`, hung off the offline pack.
   *
   * **A different `pack_index` each time**, because migration 0004 allows one
   * attempt per item and these are several attempts by one player against one
   * pack. The index is derived from the id rather than counted, so the helper
   * stays a function of its arguments.
   */
  async function aged(id: string, days: number): Promise<void> {
    const index = Number.parseInt(id.slice(-2), 16);
    await db.client.query(
      `INSERT INTO attempts
         (id, player_id, pack_id, pack_index, skill_id, is_correct,
          elapsed_ms, answered_at, created_at, session_id)
       VALUES ($1, $2, $3, $5::smallint, 1, true, 4200,
               now() - ($4 || ' days')::interval,
               now() - ($4 || ' days')::interval,
               gen_random_uuid())`,
      [id, PLAYER, PACK, String(days), index],
    );
  }

  const PACK = "018f4e3c-0000-7000-8000-0000000000f2";

  beforeEach(async () => {
    db = await freshDatabase();
    await db.client.query(
      "INSERT INTO players (id, age_band, auth_user_id) VALUES ($1, 'adult', gen_random_uuid())",
      [PLAYER],
    );
    await db.client.query(
      `INSERT INTO offline_packs (id, player_id, item_refs, pack_salt, expires_at)
       VALUES ($1, $2, '[]'::jsonb, $3, now() + interval '7 days')`,
      [PACK, PLAYER, Buffer.from("salt")],
    );
    await db.client.query(
      `INSERT INTO template_stats
         (template_id, template_version, attempts, correct, sum_expected, sum_user_rating)
       VALUES ('t-1', 1, 17, 12, 8.5, 21000)`,
    );
  });

  afterEach(async () => {
    await db.close();
  });

  it("deletes what has expired and leaves what has not", async () => {
    await aged("018f4e3c-0000-7000-8000-000000000101", 401);
    await aged("018f4e3c-0000-7000-8000-000000000102", 399);
    await db.client.query(
      `INSERT INTO diag_events (id, player_id, attempt_id, created_at)
       VALUES ($1, $2, $3, now() - interval '31 days')`,
      [
        "018f4e3c-0000-7000-8000-000000000201",
        PLAYER,
        "018f4e3c-0000-7000-8000-000000000102",
      ],
    );

    const run = await runRetention(db.client, new Date());

    expect(run.attempts).toBe(1);
    expect(run.diagEvents).toBe(1);

    const left = await db.client.query<{ id: string }>("SELECT id FROM attempts");
    expect(left.rows.map((r) => r.id)).toEqual([
      "018f4e3c-0000-7000-8000-000000000102",
    ]);
  });

  it("a second run with the same instant deletes nothing", async () => {
    await aged("018f4e3c-0000-7000-8000-000000000103", 401);
    const now = new Date();

    const first = await runRetention(db.client, now);
    const second = await runRetention(db.client, now);

    expect(first.attempts).toBe(1);
    expect(second.attempts).toBe(0);
    expect(second.diagEvents).toBe(0);
  });

  it("a spent pack is swept once nothing points at it", async () => {
    // `POST /packs` made this live. Before it, `offline_packs` was empty and
    // the gap was theoretical — the job deleted attempts and diagnosis events
    // and left every pack behind for ever.
    const spent = "018f4e3c-0000-7000-8000-0000000003a1";
    await db.client.query(
      `INSERT INTO offline_packs (id, player_id, item_refs, pack_salt, expires_at)
       VALUES ($1, $2, '[]'::jsonb, $3, now() - interval '401 days')`,
      [spent, PLAYER, Buffer.from("salt")],
    );

    const run = await runRetention(db.client, new Date());

    expect(run.offlinePacks).toBe(1);
    const left = await db.client.query<{ id: string }>("SELECT id FROM offline_packs");
    // The one issued seven days from now is untouched.
    expect(left.rows.map((r) => r.id)).toEqual([PACK]);
  });

  it("and never while an attempt still points at it", async () => {
    // **The guard that matters.** `attempts.pack_id` cascades, so deleting a
    // pack takes its answered attempts with it — the exact opposite of what a
    // retention job is for. The dates already make this unreachable; the
    // `NOT EXISTS` is what makes it unreachable by construction.
    const spent = "018f4e3c-0000-7000-8000-0000000003a2";
    await db.client.query(
      `INSERT INTO offline_packs (id, player_id, item_refs, pack_salt, expires_at)
       VALUES ($1, $2, '[]'::jsonb, $3, now() - interval '401 days')`,
      [spent, PLAYER, Buffer.from("salt")],
    );
    // An attempt young enough to survive the sweep above it, on a pack old
    // enough to be swept — which the arithmetic alone would not prevent.
    await db.client.query(
      `INSERT INTO attempts
         (id, player_id, pack_id, pack_index, skill_id, is_correct, elapsed_ms,
          answered_at, created_at, session_id)
       VALUES (gen_random_uuid(), $1, $2, 0, 1, true, 4200, now(), now(), gen_random_uuid())`,
      [PLAYER, spent],
    );

    const run = await runRetention(db.client, new Date());

    expect(run.offlinePacks).toBe(0);
    expect(run.attempts).toBe(0);
    const kept = await db.client.query("SELECT 1 FROM offline_packs WHERE id = $1", [spent]);
    expect(kept.rowCount).toBe(1);
    // And the attempt is still there, which is the thing this protects.
    expect((await db.client.query("SELECT 1 FROM attempts")).rowCount).toBe(1);
  });

  it("a spent issued item is swept the same way", async () => {
    // Nothing writes `issued_items` yet — `GET /items/next` is still 501 — so
    // this is the gap closed before it opens rather than after.
    const item = "018f4e3c-0000-7000-8000-0000000003b1";
    await db.client.query(
      `INSERT INTO issued_items (id, player_id, template_id, template_version, seed,
                                 ladder_step, issued_at)
       VALUES ($1, $2, 't-1', 1, 7, 3, now() - interval '401 days')`,
      [item, PLAYER],
    );

    const run = await runRetention(db.client, new Date());

    expect(run.issuedItems).toBe(1);
    expect((await db.client.query("SELECT 1 FROM issued_items")).rowCount).toBe(0);
  });

  it("a session's recorded movement goes when the session's attempts do", async () => {
    // **It is an attribute of a history entry, so it is swept on the entry's
    // own cutoff.** A delta kept after its attempts would be a row nothing can
    // reach; a delta swept before them would make an entry that still appears
    // in `GET /me/history` silently lose the figure it had. Reusing
    // `cutoffs.attempts` rather than declaring a third 400 is what makes the
    // two impossible to set apart.
    const session = "018f4e3c-0000-7000-8000-0000000004a1";
    await db.client.query(
      `INSERT INTO session_deltas (player_id, session_id, skill_id, rating_delta, created_at)
       VALUES ($1, $2, 1, 23.5, now() - interval '401 days')`,
      [PLAYER, session],
    );
    const young = "018f4e3c-0000-7000-8000-0000000004a2";
    await db.client.query(
      `INSERT INTO session_deltas (player_id, session_id, skill_id, rating_delta, created_at)
       VALUES ($1, $2, 1, -4.25, now() - interval '399 days')`,
      [PLAYER, young],
    );

    const run = await runRetention(db.client, new Date());

    expect(run.sessionDeltas).toBe(1);
    const left = await db.client.query<{ session_id: string }>(
      "SELECT session_id FROM session_deltas",
    );
    expect(left.rows.map((row) => row.session_id)).toEqual([young]);
  });

  it("and never while an attempt of that session is still there", async () => {
    // The same guard as the two source tables, for the same reason turned
    // round: here the row that must not vanish first is the delta, because the
    // history entry its attempts still produce would lose its figure without
    // anything recording that it had one.
    const session = "018f4e3c-0000-7000-8000-0000000004b1";
    await db.client.query(
      `INSERT INTO session_deltas (player_id, session_id, skill_id, rating_delta, created_at)
       VALUES ($1, $2, 1, 11.5, now() - interval '401 days')`,
      [PLAYER, session],
    );
    await db.client.query(
      `INSERT INTO attempts
         (id, player_id, pack_id, pack_index, skill_id, is_correct, elapsed_ms,
          answered_at, created_at, session_id)
       VALUES (gen_random_uuid(), $1, $2, 77, 1, true, 4200, now(), now(), $3)`,
      [PLAYER, PACK, session],
    );

    const run = await runRetention(db.client, new Date());

    expect(run.sessionDeltas).toBe(0);
    expect((await db.client.query("SELECT 1 FROM session_deltas")).rowCount).toBe(1);
  });

  it("the job runs as the role that will actually run it", async () => {
    // **The grant is the one thing a suite running as the owner cannot see.**
    // PostgreSQL requires SELECT on every column a DELETE's condition reads,
    // including the target table's own, so a new table granted DELETE and not
    // SELECT is green here for ever and `permission denied` in the nightly job.
    // Every statement is exercised, so this covers the tables that already
    // existed as well as the newest one.
    await aged("018f4e3c-0000-7000-8000-0000000004c1", 401);
    await db.client.query(
      `INSERT INTO session_deltas (player_id, session_id, skill_id, rating_delta, created_at)
       VALUES ($1, gen_random_uuid(), 1, 3.5, now() - interval '401 days')`,
      [PLAYER],
    );

    await db.client.query("SET ROLE retention_job");
    try {
      const run = await runRetention(db.client, new Date());
      expect(run.attempts).toBe(1);
      expect(run.sessionDeltas).toBe(1);
    } finally {
      await db.client.query("RESET ROLE");
    }
  });

  it("the aggregates calibration reads are untouched by either run", async () => {
    // Deleting attempts is only safe because `template_stats` is maintained on
    // write. If a future path starts deriving from raw rows, this breaks a test
    // rather than a player's history.
    await aged("018f4e3c-0000-7000-8000-000000000104", 401);
    const before = await db.client.query("SELECT * FROM template_stats");

    const now = new Date();
    await runRetention(db.client, now);
    await runRetention(db.client, now);

    const after = await db.client.query("SELECT * FROM template_stats");
    expect(after.rows).toEqual(before.rows);
  });
});
