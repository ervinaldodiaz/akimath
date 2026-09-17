import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import { buildTemplateGolden } from "../src/golden.js";
import { buildPrngGolden } from "../src/prng/golden.js";
import { buildRatingGolden } from "../src/rating/golden.js";

/**
 * Nothing in these artifacts that can exceed 2^53 is written as a JSON number,
 * and **that already cost a migration.**
 *
 * `offline_packs.template_refs` stored a seed as a JSON number and `JSON.parse`
 * rounded it: 9223372036854775807 came back 9223372036854776000. Because
 * splitmix64 avalanches, a seed off by one rederives an unrelated item and every
 * schema is still happy.
 */

/**
 * The committed artifacts are **replayed from disk**, not recomputed.
 *
 * A test that calls the builder twice and compares the results to each other
 * proves the builder is deterministic and nothing else — it would stay green
 * through any behaviour change, because both sides move together. Reading the
 * file is what makes these regression gates.
 *
 * They are not correctness proofs and are not treated as any. The PRNG's
 * correctness comes from Vigna's compiled reference, the rating's from
 * Glickman's published worked example, and the reference template's from an item
 * that is actually shipping in `app/assets/packs/starter.json`.
 */
function committed(name: string): unknown {
  return JSON.parse(
    readFileSync(fileURLToPath(new URL(`../golden/${name}`, import.meta.url)), "utf8"),
  );
}

/** What the emitter writes, as JSON sees it. */
const asJson = (value: unknown): unknown => JSON.parse(JSON.stringify(value));

/**
 * The same digits parsed as a JSON *number*, which is where they stop
 * surviving.
 *
 * It is compared as a **string**, because in JavaScript the literal
 * `9223372036854775807` is itself already `9223372036854776000` — comparing the
 * two numbers compares two copies of the same rounding, which is how a control
 * quietly stops controlling anything.
 */
const roundedByJsonNumber = (): number =>
  JSON.parse('{"n":9223372036854775807}').n as number;

describe("the committed golden artifacts are what the code produces", () => {
  it("the PRNG vector", () => {
    const golden = buildPrngGolden();
    expect(committed("prng.golden.json")).toEqual(asJson(golden));
    expect(golden.seeds.length).toBeGreaterThan(0);
    // eslint-disable-next-line no-console
    console.log(`  golden · prng → ${golden.seeds.length} seeds`);
  });

  it("the template corpus", () => {
    const golden = buildTemplateGolden();
    expect(committed("templates.golden.json")).toEqual(asJson(golden));
    expect(golden.rows.length).toBeGreaterThan(0);
    // eslint-disable-next-line no-console
    console.log(`  golden · templates → ${golden.rows.length} rows`);
  });

  it("the rating vector", () => {
    const golden = buildRatingGolden();
    expect(committed("rating.golden.json")).toEqual(asJson(golden));
    expect(golden.sessions.length).toBeGreaterThan(0);
    expect(golden.decays.length).toBeGreaterThan(0);
    // eslint-disable-next-line no-console
    console.log(
      `  golden · rating → ${golden.sessions.length} sessions, ${golden.decays.length} decays`,
    );
  });
});

describe("nothing that can exceed 2^53 is written as a JSON number", () => {
  it("every seed, word and rational component is a string", () => {
    const prng = committed("prng.golden.json") as {
      seeds: { seed: unknown; words: unknown[]; d6: unknown[] }[];
    };
    for (const row of prng.seeds) {
      expect(typeof row.seed).toBe("string");
      for (const word of [...row.words, ...row.d6]) expect(typeof word).toBe("string");
    }

    const templates = committed("templates.golden.json") as {
      rows: { seed: unknown; answer: { numerator: unknown; denominator: unknown } }[];
    };
    for (const row of templates.rows) {
      expect(typeof row.seed).toBe("string");
      expect(typeof row.answer.numerator).toBe("string");
      expect(typeof row.answer.denominator).toBe("string");
    }
  });

  it("and the extremes survive the round trip they would have broken", () => {
    const prng = committed("prng.golden.json") as { seeds: { seed: string }[] };
    const seeds = prng.seeds.map((row) => BigInt(row.seed));

    expect(seeds).toContain(9223372036854775807n);
    expect(seeds).toContain(-9223372036854775808n);
    const asNumber: number = roundedByJsonNumber();
    expect(String(asNumber)).not.toBe("9223372036854775807");
    expect(String(BigInt("9223372036854775807"))).toBe("9223372036854775807");
  });
});

describe("the rating vector is byte-exact, which floating point usually is not", () => {
  it("every stored figure is already a float32", () => {
    const golden = buildRatingGolden();
    for (const { after } of [...golden.sessions, ...golden.decays]) {
      expect(Math.fround(after.rating)).toBe(after.rating);
      expect(Math.fround(after.deviation)).toBe(after.deviation);
    }
  });
});
