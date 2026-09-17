import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    // Pinned at vitest's current default rather than raised, and written down
    // so a future default change cannot quietly loosen the gate.
    //
    // It is **not** ~57x headroom over the slowest test any more, which is what
    // this comment claimed while `test/pack/cli.test.ts` spawned a subprocess
    // per case and took seconds. That file now carries its own explicit 30s per
    // spawning case, stated where the spawn is, precisely so this figure can
    // stay at 5s and keep every test that does not shell out honest. Raising it
    // globally would have bought the same green run by exempting every test in
    // the package that has no business taking five seconds.
    //
    // What it does and does not do, measured rather than assumed: a test that
    // awaits a promise nobody resolves fails here in ~2s, but a synchronous
    // loop with no exit is *not* interrupted — vitest's timer cannot preempt a
    // busy worker, and a probe was still spinning after 20s. The bounds that
    // survive that case are outside vitest: `timeout-minutes` on every job in
    // .github/workflows/ci.yml, and the per-command deadline in
    // .claude/hooks/verify-gate.sh.
    testTimeout: 5_000,
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov"],
      reportsDirectory: "coverage",
      // Mirrors packages/server: only the pure modules participate. The one
      // module that touches the filesystem lives behind src/adapters/ and is
      // excluded here on purpose (D9).
      include: ["src/**/*.ts"],
      exclude: ["src/adapters/**"],
    },
  },
});
