import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { AUTHORED_PACK_PATH } from "../authored-pack.js";

/**
 * The adapter, run for real.
 *
 * The assembly is tested without a filesystem next door. What is left here is
 * exactly what a subprocess is needed for: does a refusal write anything, and
 * does a failure damage what was already committed. Both are answerable only by
 * running the thing.
 */

const CLI = fileURLToPath(new URL("../../src/adapters/build-pack.ts", import.meta.url));
const REAL_MISCONCEPTIONS = fileURLToPath(
  new URL("../../content/misconceptions.json", import.meta.url),
);
const AUTHORED = AUTHORED_PACK_PATH;

/**
 * The runner, resolved from this package's own `node_modules` rather than
 * through `npx`.
 *
 * `npx tsx` costs 2.99–5.48s per spawn against 1.49–2.07s for the binary it
 * ends up running — measured on 2026-09-17 — and the difference is resolution,
 * not work. It is also a second failure mode with nothing to do with this code:
 * `npx` reaches for the shared npm lock and, with several worktrees running
 * their suites at once, answers `ECOMPROMISED` and tries to install from the
 * network. `npm run build:pack` resolves `tsx` from exactly this path, so this
 * is also the closer imitation of the real command.
 */
const TSX = fileURLToPath(new URL("../../node_modules/.bin/tsx", import.meta.url));

/**
 * How long one of those spawns is allowed to take.
 *
 * Every case below compiles and runs a TypeScript entry point in a subprocess,
 * which is seconds rather than the milliseconds the package's 5s default was
 * written for. At load average 41 the spawns measured 0.7–4.2s and one case
 * timed out; the failure named no assertion, so the gate was reporting machine
 * load as a defect in the pack builder. This is the honest bound for what these
 * cases actually do, and it is set per case so every non-spawning test in the
 * package stays held to 5s.
 */
const SPAWN_TIMEOUT_MS = 30_000;

interface Run {
  readonly status: number;
  readonly stderr: string;
  readonly stdout: string;
}

function run(args: readonly string[]): Run {
  try {
    const stdout = execFileSync(TSX, [CLI, ...args], { encoding: "utf8" });
    return { status: 0, stdout, stderr: "" };
  } catch (error) {
    const e = error as { status?: number | null; stdout?: string; stderr?: string };
    // A process that never started, or one a signal killed, has no exit status.
    // Reporting either as `1` would let a refusal case pass on a missing `tsx`
    // instead of saying so (TEST-1).
    if (typeof e.status !== "number") throw error;
    return { status: e.status, stdout: e.stdout ?? "", stderr: e.stderr ?? "" };
  }
}

function workspace(declaration: unknown): { dir: string; declarationPath: string; out: string } {
  const dir = mkdtempSync(path.join(tmpdir(), "akimath-pack-"));
  const declarationPath = path.join(dir, "declaration.json");
  writeFileSync(declarationPath, JSON.stringify(declaration), "utf8");
  return { dir, declarationPath, out: path.join(dir, "out.json") };
}

const validDeclaration = (over: Record<string, unknown> = {}): unknown => ({
  pack_salt: "a1b2c3d4e5f60718293a4b5c6d7e8f90",
  seed_base: "1000",
  issued_at: "2026-08-18T00:00:00.000Z",
  expires_at: "2026-11-18T00:00:00.000Z",
  sources: [{ kind: "authored", path: AUTHORED, skill_id: 1 }],
  ...over,
});

describe("the builder writes a pack", () => {
  it("emits one and reports what it built", () => {
    const w = workspace(validDeclaration());
    const r = run(["--declaration", w.declarationPath, "--out", w.out]);

    expect(r.status).toBe(0);
    expect(r.stdout).toMatch(/80 items|70 items/);
    expect(JSON.parse(readFileSync(w.out, "utf8"))).toMatchObject({ pack_format_version: 1 });
  }, SPAWN_TIMEOUT_MS);
});

/**
 * The damage a failed build must not do, named after the run that did it:
 * `dump-schema.sh` truncated its output before the producer had run, so a bad
 * run destroyed the committed artifact.
 */
describe("a refusal writes nothing and damages nothing", () => {
  it("exits non-zero and leaves no file where none existed", () => {
    const w = workspace(validDeclaration({ pack_salt: "not-a-salt" }));
    const r = run(["--declaration", w.declarationPath, "--out", w.out]);

    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/pack_salt/);
    expect(() => readFileSync(w.out, "utf8")).toThrow();
  }, SPAWN_TIMEOUT_MS);

  it("leaves a previously written pack exactly as it was", () => {
    const w = workspace(validDeclaration());
    run(["--declaration", w.declarationPath, "--out", w.out]);
    const before = readFileSync(w.out, "utf8");

    writeFileSync(w.declarationPath, JSON.stringify(validDeclaration({ seed_base: "oops" })), "utf8");
    const r = run(["--declaration", w.declarationPath, "--out", w.out]);

    expect(r.status).toBe(1);
    expect(readFileSync(w.out, "utf8")).toBe(before);
  }, SPAWN_TIMEOUT_MS);

  it("refuses a pack the frozen validator rejects, naming the tag", () => {
    const w = workspace(validDeclaration());
    const broken = path.join(w.dir, "broken.json");
    writeFileSync(broken, JSON.stringify({ items: [{
      id: "hole-off-the-end", ladder_step: 1, answer: "8",
      stimulus: { kind: "numberSeries", payload: { terms: [2, 4, 6], unknown_index: 99 } },
    }] }), "utf8");
    writeFileSync(
      w.declarationPath,
      JSON.stringify(validDeclaration({ sources: [{ kind: "authored", path: broken, skill_id: 1 }] })),
      "utf8",
    );

    const r = run(["--declaration", w.declarationPath, "--out", w.out]);

    expect(r.status).toBe(1);
    expect(r.stderr).toMatch(/unknown_index_out_of_range/);
    expect(() => readFileSync(w.out, "utf8")).toThrow();
  }, SPAWN_TIMEOUT_MS);
});

/**
 * The assembly tests prove a pack *can* keep six families; this proves the one
 * in the tree does.
 *
 * They run against their own declaration, so editing
 * `content/pack.declaration.json` down to templates only would leave every one
 * of them green while the shipped artifact offered a player one kind of
 * question. That is the regression this whole change is shaped to prevent, so
 * it is asserted against the artifact itself.
 */
describe("the committed pack is the one the declaration produces", () => {
  const committed = fileURLToPath(new URL("../../pack/starter.json", import.meta.url));

  it("re-emitting leaves it byte-identical, before CI says so", () => {
    const before = readFileSync(committed, "utf8");
    const r = run([]);

    expect(r.status).toBe(0);
    expect(readFileSync(committed, "utf8")).toBe(before);
  }, SPAWN_TIMEOUT_MS);

  it("keeps all six families, in the pack we actually ship", () => {
    const pack = JSON.parse(readFileSync(committed, "utf8")) as {
      items: { stimulus: { kind: string } }[];
    };
    const families = new Set(pack.items.map((item) => item.stimulus.kind));

    expect([...families].sort()).toEqual([
      "analogy",
      "arithmetic",
      "figurate",
      "hiddenOperation",
      "matrix",
      "numberSeries",
    ]);
    expect(pack.items.length).toBeGreaterThan(70);
  });
});
