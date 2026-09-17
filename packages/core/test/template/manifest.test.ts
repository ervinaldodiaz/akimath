import { describe, expect, it } from "vitest";

import { DigestSchema } from "@akimath/contract";

import {
  fromManifestEntry,
  templateRefOf,
  toDigestEntry,
  toManifestEntry,
} from "../../src/manifest.js";
import type { TemplateRef } from "../../src/template.js";

/**
 * How a manifest entry is written into `offline_packs.item_refs` and read back.
 *
 * **A seed past 2^53 is where a naive encoding breaks, and it breaks silently.**
 * splitmix64 avalanches, so an item rederived from a seed off by one is
 * unrelated rather than similar — nothing downstream looks wrong, it is just a
 * different item. That is why the seed travels as a string and why a JSON number
 * is *refused* rather than converted: by the time it is a number the precision
 * is already gone, and converting would launder the bug. Migration 0002 refuses
 * it for the same reason.
 *
 * **The field names are the column's, not the API's** — the pack format and the
 * column are snake_case where a response is camelCase, and renaming either to
 * match the other is how the two stop being the same thing.
 *
 * **An entry says which kind it is** rather than leaving it to be inferred.
 * Guessing from the fields present is how a typo in `template_id` quietly
 * becomes "this must be a digest"; nothing has issued a pack in production, so
 * there is no kindless entry to be lenient about.
 */
const INT64_MAX = 9223372036854775807n;
const INT64_MIN = -9223372036854775808n;

const ref = (seed: bigint): TemplateRef => ({
  templateId: "arith.integer.subtract",
  templateVersion: 2,
  seed,
  ladderStep: 3,
});

describe("a reference survives being written down", () => {
  it("round-trips, including both ends of the signed range and a seed past 2^53", () => {
    for (const seed of [0n, 1n, 389n, 9007199254740993n, INT64_MAX, INT64_MIN]) {
      const read = fromManifestEntry(toManifestEntry(ref(seed)));
      expect(read?.kind, seed.toString()).toBe("template");
      expect(templateRefOf(read!), seed.toString()).toEqual(ref(seed));
    }
  });

  it("and the seed is written as a string, never as a number", () => {
    expect(toManifestEntry(ref(INT64_MAX)).seed).toBe("9223372036854775807");
    expect(typeof toManifestEntry(ref(1n)).seed).toBe("string");
  });

  it("it says which kind it is, rather than leaving it to be inferred from the fields present", () => {
    expect(toManifestEntry(ref(1n)).kind).toBe("template");
    expect(fromManifestEntry({ ...toManifestEntry(ref(1n)), kind: undefined })).toBeNull();
    expect(fromManifestEntry({ ...toManifestEntry(ref(1n)), kind: "templates" })).toBeNull();
  });

  it("the field names are the column's snake_case, not the API's camelCase", () => {
    expect(Object.keys(toManifestEntry(ref(1n))).sort()).toEqual([
      "kind",
      "ladder_step",
      "seed",
      "template_id",
      "template_version",
    ]);
  });
});

describe("and an entry that is not one is refused", () => {
  const entry = (over: Record<string, unknown> = {}): unknown => ({
    ...toManifestEntry(ref(1n)),
    ...over,
  });

  it("a numeric seed is refused rather than converted, which migration 0002 does for the same reason", () => {
    expect(fromManifestEntry(entry({ seed: 1477776061723855037 }))).toBeNull();
    expect(fromManifestEntry(entry({ seed: 1 }))).toBeNull();
  });

  it("a seed that is a string but not a number, though a negative one is fine because the column is signed", () => {
    for (const seed of ["", "1.5", "0x10", "1e3", " 1", "nine"]) {
      expect(fromManifestEntry(entry({ seed })), seed).toBeNull();
    }
    expect(templateRefOf(fromManifestEntry(entry({ seed: "-1" }))!)?.seed).toBe(-1n);
  });

  it("a missing or mistyped field", () => {
    for (const over of [
      { template_id: undefined },
      { template_id: 7 },
      { template_version: "2" },
      { template_version: 2.5 },
      { ladder_step: undefined },
      { ladder_step: "3" },
      { ladder_step: 3.5 },
    ]) {
      expect(fromManifestEntry(entry(over)), JSON.stringify(over)).toBeNull();
    }
  });

  it("and something that is not an object at all", () => {
    for (const value of [null, undefined, 3, "x", [toManifestEntry(ref(1n))]]) {
      expect(fromManifestEntry(value), JSON.stringify(value ?? null)).toBeNull();
    }
  });
})
describe("and an item nobody can rederive is written down by its digest", () => {
  const DIGEST = "a".padEnd(64, "b");

  it("round-trips", () => {
    const entry = toDigestEntry({ digest: DIGEST, skillId: 1 });

    expect(entry).toEqual({ kind: "digest", digest: DIGEST, skill_id: 1 });
    expect(fromManifestEntry(entry)).toEqual(entry);
  });

  it("and has no reference, which is the whole reason it exists: an authored item carries no template, so the digest is what identifies it", () => {
    expect(templateRefOf(toDigestEntry({ digest: DIGEST, skillId: 1 }))).toBeNull();
  });

  it("it carries a skill, because `attempts.skill_id` is NOT NULL and there is no template to ask", () => {
    expect(toDigestEntry({ digest: DIGEST, skillId: 4 }).skill_id).toBe(4);
    expect(fromManifestEntry({ kind: "digest", digest: DIGEST })).toBeNull();
    expect(fromManifestEntry({ kind: "digest", digest: DIGEST, skill_id: 0 })).toBeNull();
    expect(fromManifestEntry({ kind: "digest", digest: DIGEST, skill_id: 1.5 })).toBeNull();
  });

  it("a digest that is not one is refused", () => {
    const notADigest: ReadonlyArray<readonly [why: string, digest: string]> = [
      ["empty", ""],
      ["far too short", "abc"],
      ["uppercase", "A".padEnd(64, "b")],
      ["one character short", "a".padEnd(63, "b")],
      ["one character long", "a".padEnd(65, "b")],
      ["trailing space, which only an anchored pattern rejects", `${"a".padEnd(64, "b")} `],
    ];
    for (const [why, digest] of notADigest) {
      expect(fromManifestEntry({ kind: "digest", digest, skill_id: 1 }), why).toBeNull();
    }
  });

  it("and its shape agrees with the contract's, which is the authority — the rule exists twice because the public surface imports no package, so both are run over the same probes", () => {
    const probes = [
      "a".padEnd(64, "b"),
      "0".padEnd(64, "9"),
      "",
      "A".padEnd(64, "b"),
      "a".padEnd(63, "b"),
      "a".padEnd(65, "b"),
      "g".padEnd(64, "a"),
    ];
    expect(probes.length).toBeGreaterThan(0);
    for (const probe of probes) {
      const contractAccepts = DigestSchema.safeParse(probe).success;
      const mineAccepts =
        fromManifestEntry({ kind: "digest", digest: probe, skill_id: 1 }) !== null;
      expect(mineAccepts, probe).toBe(contractAccepts);
    }
  });
});
