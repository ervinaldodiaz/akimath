import { describe, expect, it } from "vitest";

import { parseDeclaration } from "../../src/pack/declaration.js";

/** A declaration with everything valid, so each case can break exactly one thing. */
const valid = (over: Record<string, unknown> = {}): unknown => ({
  pack_salt: "a1b2c3d4e5f60718293a4b5c6d7e8f90",
  seed_base: "1000",
  issued_at: "2026-08-18T00:00:00.000Z",
  expires_at: "2026-11-18T00:00:00.000Z",
  sources: [
    { kind: "template", template_id: "arith.integer.subtract", template_version: 2, ladder_step: 3, count: 5 },
    { kind: "authored", path: "../../app/assets/packs/starter.json", skill_id: 1 },
  ],
  ...over,
});

/**
 * The seed base parses to a bigint, because `TemplateRef.seed` is one and JSON
 * has no such type — so the declaration spells it as a string and the parser is
 * where it stops being one. A number would silently lose precision past 2^53.
 */
describe("a declaration says what to build", () => {
  it("reads the salt, the seed base, the window and the sources", () => {
    const d = parseDeclaration(valid());

    expect(d.packSalt).toBe("a1b2c3d4e5f60718293a4b5c6d7e8f90");
    expect(d.seedBase).toBe(1000n);
    expect(d.sources).toHaveLength(2);
    expect(d.sources[0]).toMatchObject({ kind: "template", count: 5 });
    expect(d.sources[1]).toMatchObject({ kind: "authored" });
  });

  it("keeps the declared order, because the pack's order is a product decision", () => {
    const d = parseDeclaration(
      valid({
        sources: [
          { kind: "authored", path: "a.json", skill_id: 1 },
          { kind: "template", template_id: "t", template_version: 1, ladder_step: 1, count: 1 },
          { kind: "authored", path: "b.json", skill_id: 1 },
        ],
      }),
    );

    expect(d.sources.map((s) => s.kind)).toEqual(["authored", "template", "authored"]);
  });

  it("carries a seed base far past what a double can hold", () => {
    const big = "9007199254740993";
    expect(parseDeclaration(valid({ seed_base: big })).seedBase).toBe(BigInt(big));
  });
});

/**
 * A malformed declaration is refused, naming the field.
 *
 * One case per thing a hand-edited declaration can get wrong, each paired with
 * the token the refusal has to carry. The field is in the message because a
 * declaration is content a person edits by hand, and "invalid declaration"
 * sends them reading the whole file.
 *
 * Shape and range are different checks, and a regex alone passes every
 * timestamp below. The falsification pass found them: loosening the day bound
 * left every other case green.
 */
describe("a malformed declaration is refused, naming the field", () => {
  const cases: ReadonlyArray<readonly [string, Record<string, unknown>, string]> = [
    ["a salt that is not 32 hex characters", { pack_salt: "nope" }, "pack_salt"],
    ["a salt in upper case", { pack_salt: "A1B2C3D4E5F60718293A4B5C6D7E8F90" }, "pack_salt"],
    ["a seed base that is not a string", { seed_base: 1000 }, "seed_base"],
    ["a seed base that is not a number at all", { seed_base: "many" }, "seed_base"],
    ["a window that ends before it starts", { expires_at: "2026-01-01T00:00:00.000Z" }, "expires_at"],
    ["a timestamp that is not a timestamp", { issued_at: "last tuesday" }, "issued_at"],
    ["a thirteenth month", { issued_at: "2026-13-01T00:00:00.000Z" }, "issued_at"],
    ["a thirty-first of February", { issued_at: "2026-02-31T00:00:00.000Z" }, "issued_at"],
    ["a zeroth day", { issued_at: "2026-01-00T00:00:00.000Z" }, "issued_at"],
    ["a twenty-fifth hour", { issued_at: "2026-01-01T25:00:00.000Z" }, "issued_at"],
    ["a sixtieth minute", { issued_at: "2026-01-01T00:60:00.000Z" }, "issued_at"],
    ["no milliseconds", { issued_at: "2026-01-01T00:00:00Z" }, "issued_at"],
    ["a local time with an offset", { issued_at: "2026-01-01T00:00:00.000-06:00" }, "issued_at"],
    ["no sources at all", { sources: [] }, "sources"],
    ["a source of an unknown kind", { sources: [{ kind: "divination", skill_id: 1 }] }, "kind"],
    ["a template source with no count", { sources: [{ kind: "template", template_id: "t", template_version: 1, ladder_step: 1 }] }, "count"],
    ["a ladder step outside 1..20", { sources: [{ kind: "template", template_id: "t", template_version: 1, ladder_step: 21, count: 1 }] }, "ladder_step"],
    ["an authored source with no path", { sources: [{ kind: "authored", skill_id: 1 }] }, "path"],
    ["a source with no skill", { sources: [{ kind: "authored", path: "a.json" }] }, "skill_id"],
  ];

  for (const [name, over, field] of cases) {
    it(name, () => {
      expect(() => parseDeclaration(valid(over))).toThrow(new RegExp(field));
    });
  }

  it("refuses something that is not an object at all", () => {
    for (const junk of [null, 42, "text", []]) {
      expect(() => parseDeclaration(junk)).toThrow();
    }
  });
});

/**
 * One fact, one place.
 *
 * The template knows which skill it exercises (`Template.skillId`). A
 * declaration that says so too is a second place to be wrong, and the wrong one
 * would be the pack's — items filed under a skill their template does not
 * exercise, rated against the wrong `user_skills` row. Refused rather than
 * ignored, because an ignored field looks like it works.
 *
 * It is also gone from the parsed shape rather than merely unread: `build.ts`
 * resolves the skill from the template, and a `skillId` surviving here would
 * give it something to prefer.
 */
describe("a template source does not state its skill", () => {
  const templateSource = (over: Record<string, unknown> = {}) => ({
    kind: "template",
    template_id: "arith.integer.subtract",
    template_version: 2,
    ladder_step: 3,
    count: 5,
    ...over,
  });

  it("reads one that omits it, and drops the field rather than leaving it unread", () => {
    const d = parseDeclaration(valid({ sources: [templateSource()] }));

    expect(d.sources[0]).toMatchObject({ kind: "template", templateId: "arith.integer.subtract" });
    expect(d.sources[0]).not.toHaveProperty("skillId");
  });

  it("and refuses one that states it, rather than ignoring it", () => {
    expect(() => parseDeclaration(valid({ sources: [templateSource({ skill_id: 1 })] })))
      .toThrow(/skill_id/);
  });

  it("while an authored source still needs one, because nothing else knows", () => {
    expect(() => parseDeclaration(valid({ sources: [{ kind: "authored", path: "a.json" }] })))
      .toThrow(/skill_id/);
  });
});
