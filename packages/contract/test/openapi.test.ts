import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { ATTEMPT_ELAPSED_MS_MAX } from "../src/openapi/api-schemas.js";
import { buildOpenApiDocument, OPENAPI_VERSION } from "../src/openapi/document.js";
import { CONTRACT_ROOT } from "./fixture-files.js";

/**
 * What the emitted specification must and must not contain.
 *
 * Two of these enforce invariants from `ARCHITECTURE.md` §4 against the
 * **document** rather than against code, because they are properties of the
 * wire — *the prompt travels rendered, the answer never travels online* — and
 * the wire description is the only place they can be checked before an endpoint
 * exists.
 */
/**
 * **Located by walking up, never by counting `..` segments.**
 * `fixture-files.ts` says why and this file learned it the hard way: a fixed
 * relative path lands nowhere inside Stryker's sandbox copy of the package, so
 * this whole file silently did not run under mutation testing — and every
 * mutant in `document.ts` survived, all 104 of them, because the test that
 * would have killed them was never executed.
 */
const committed = JSON.parse(
  readFileSync(join(CONTRACT_ROOT, "openapi.json"), "utf8"),
) as Record<string, unknown>;

/** Every node in the document, with the path that reaches it. */
function walk(node: unknown, path = ""): Array<{ path: string; node: unknown }> {
  const here = [{ path, node }];
  if (Array.isArray(node)) {
    return here.concat(node.flatMap((item, i) => walk(item, `${path}[${i}]`)));
  }
  if (typeof node === "object" && node !== null) {
    return here.concat(
      Object.entries(node).flatMap(([key, value]) =>
        walk(value, path === "" ? key : `${path}.${key}`),
      ),
    );
  }
  return here;
}

const NODES = walk(committed);
const KEYS = NODES.flatMap(({ path, node }) =>
  typeof node === "object" && node !== null && !Array.isArray(node)
    ? Object.keys(node).map((key) => ({ path, key }))
    : [],
);

/**
 * **Emitted in-process, which is only meaningful because nothing ambient is
 * read.** That is `ARCHITECTURE.md` §2's whole reason for the document living
 * in `packages/contract`: if building it opened a socket or reached for
 * `DATABASE_URL`, building it twice would be flaky rather than green.
 */
describe("the committed document is what the code produces", () => {
  it("matches a fresh emission exactly", () => {
    expect(committed).toEqual(JSON.parse(JSON.stringify(buildOpenApiDocument())));
  });

  it("walked a real document", () => {
    expect(NODES.length).toBeGreaterThan(100);
    // eslint-disable-next-line no-console
    console.log(`  openapi · ${NODES.length} nodes, ${KEYS.length} keys`);
  });

  it("needs no server, no database and no environment to build", () => {
    expect(buildOpenApiDocument()).toEqual(buildOpenApiDocument());
  });
});

/**
 * Each forbidden spelling below is 2020-12's or draft-7's way of saying
 * something 3.0.3 says differently, and each is swept over the **whole**
 * document rather than over `components.schemas`: a schema is not the only
 * place one can appear.
 */
describe("it is OpenAPI 3.0.3, not a later dialect wearing the number", () => {
  it("declares the version", () => {
    expect(committed["openapi"]).toBe(OPENAPI_VERSION);
    expect(OPENAPI_VERSION).toBe("3.0.3");
  });

  it("carries none of the later spellings anywhere", () => {
    const forbidden = ["$schema", "const", "propertyNames", "prefixItems", "$defs", "unevaluatedProperties"];
    const found = KEYS.filter((k) => forbidden.includes(k.key));
    expect(found.map((k) => `${k.path}.${k.key}`)).toEqual([]);
  });

  it("expresses an exclusive bound as a boolean, never as a number", () => {
    for (const { path, node } of NODES) {
      if (typeof node !== "object" || node === null || Array.isArray(node)) continue;
      for (const key of ["exclusiveMinimum", "exclusiveMaximum"]) {
        if (key in node) {
          expect(typeof (node as Record<string, unknown>)[key], `${path}.${key}`).toBe(
            "boolean",
          );
        }
      }
    }
  });

  it("never expresses a type as an array", () => {
    for (const { path, node } of NODES) {
      if (typeof node === "object" && node !== null && "type" in node) {
        expect(Array.isArray((node as Record<string, unknown>)["type"]), path).toBe(false);
      }
    }
  });
});

/**
 * `ARCHITECTURE.md` §2, and the frozen pack format already obeys the same rule:
 * variance lives inside an opaque payload, not in a union the client has to
 * discriminate. The second case is the control — "no unions" is also true of a
 * document with no varying shapes at all, which would mean the rule had never
 * been exercised.
 */
describe("no response is polymorphic", () => {
  it("contains no oneOf, anyOf, allOf or discriminator", () => {
    const found = KEYS.filter((k) =>
      ["oneOf", "anyOf", "allOf", "discriminator"].includes(k.key),
    );
    expect(found.map((k) => `${k.path}.${k.key}`)).toEqual([]);
  });

  it("and the variance that does exist is an opaque object", () => {
    const schemas = (committed["components"] as { schemas: Record<string, Record<string, unknown>> })
      .schemas;
    const verdict = schemas["Verdict"] as { properties: Record<string, unknown> };
    expect(verdict.properties["payload"]).toEqual({
      type: "object",
      additionalProperties: {},
    });
  });
});

/**
 * `ARCHITECTURE.md` §4's wire invariants, asserted against the **document**
 * rather than against code: before an endpoint exists, the wire description is
 * the only place they can be checked.
 *
 * **Nothing names a template, a version or a seed.** The server emits and
 * records those three and they "never appear in the response" — they
 * reconstruct the problem. The last case is that sweep's control: over a
 * document that *does* contain the forbidden names the same predicate must
 * fire, or it passes for a regex that matches nothing (PROC-11).
 *
 * **The item response is the item id, the prompt and the keypad, and nothing
 * else.** `ARCHITECTURE.md`:202 still lists `options`, contradicting §4's own
 * resolution; a field offering a set of answers to choose from is a different
 * product, and that line is the one that is wrong.
 *
 * **A submission asserts no verdict of its own.** §4: the sync endpoint "does
 * not accept an `ok` field — that is what makes the invariant true by
 * construction rather than by discipline", and a schema is where
 * by-construction lives.
 *
 * **A submission names exactly one source, and the schema cannot say so.**
 * `attempts_one_source` is `(issued_item_id)` XOR `(pack_id, pack_index)`, so
 * the wire mirrors it with `itemId` and `packRef` **both optional**. A `oneOf`
 * would state the rule properly and `downconvert.ts` refuses one — 3.0.3 has no
 * general union and §2 keeps the surface flat for a hand-written Dart client —
 * so the XOR is enforced where it can be, by the server's reader as a 400 and
 * by the database CHECK behind it, and the operation's `description` says out
 * loud what the shape cannot. `packRef` is inlined rather than `$ref`-ed, which
 * is what this emitter does everywhere, so it is compared against the named
 * component instead of restated.
 *
 * **A verdict echoes whichever source the submission named.** A pack attempt
 * has no `itemId` — identity is `(packId, index)` — so a required one was a
 * field the server could not fill for half the paths it serves. Order is the
 * primary correlation and the echo is what lets a client check it rather than
 * trust it; the echoed shapes are the submission's own, not a second spelling.
 *
 * **Time on task is bounded, because nothing else bounds it.**
 * `attempts.elapsed_ms` is NOT NULL and client-supplied: `issued_at → clientTs`
 * is wall-clock latency rather than time on task, and a pack item has no
 * `issued_at` at all. Unbounded, it is a row saying somebody spent forty days on
 * one subtraction, and it lands in `template_stats` and then in calibration. It
 * is **refused** above the ceiling rather than clamped: a clamped value is a lie
 * that passes every gate downstream of it.
 */
describe("the answer never travels and the prompt travels rendered", () => {
  it("no property anywhere names a template, a version or a seed", () => {
    const rederivationKey = /^(template_?id|template_?version|seed)$/i;
    const offenders = NODES.flatMap(({ path, node }) =>
      path.endsWith("properties") && typeof node === "object" && node !== null
        ? Object.keys(node)
            .filter((name) => rederivationKey.test(name))
            .map((name) => `${path}.${name}`)
        : [],
    );
    expect(offenders).toEqual([]);
  });

  it("the item response is the item id, the prompt and the keypad — and nothing else", () => {
    const schemas = (committed["components"] as { schemas: Record<string, Record<string, unknown>> })
      .schemas;
    const item = schemas["ItemResponse"] as {
      properties: Record<string, unknown>;
      required: string[];
    };
    expect(Object.keys(item.properties).sort()).toEqual(["itemId", "keypad", "prompt"]);
    expect(item.required.sort()).toEqual(["itemId", "keypad", "prompt"]);
  });

  it("a submission asserts no verdict of its own", () => {
    const schemas = (committed["components"] as { schemas: Record<string, Record<string, unknown>> })
      .schemas;
    const submission = schemas["AttemptSubmission"] as { properties: Record<string, unknown> };
    for (const claim of ["ok", "correct", "isCorrect", "verdict", "score"]) {
      expect(Object.keys(submission.properties)).not.toContain(claim);
    }
  });

  it("a submission names exactly one source, and the schema cannot say so", () => {
    const schemas = (committed["components"] as { schemas: Record<string, Record<string, unknown>> })
      .schemas;
    const submission = schemas["AttemptSubmission"] as {
      properties: Record<string, Record<string, unknown>>;
      required: string[];
    };

    expect(Object.keys(submission.properties).sort()).toEqual(
      ["answer", "clientTs", "elapsedMs", "itemId", "packRef", "sessionId"],
    );
    expect([...submission.required].sort()).toEqual(
      ["answer", "clientTs", "elapsedMs", "sessionId"],
    );
    expect(submission.properties["packRef"]).toEqual(schemas["OfflinePackRef"]);
    const submit = ((committed["paths"] as Record<string, Record<string, Record<string, unknown>>>)
      ["/attempts"] as Record<string, Record<string, unknown>>)["post"] as {
      description: string;
    };
    expect(submit.description).toMatch(/exactly one/i);
  });

  it("a verdict echoes whichever source the submission named", () => {
    const schemas = (committed["components"] as { schemas: Record<string, Record<string, unknown>> })
      .schemas;
    const verdict = schemas["Verdict"] as {
      properties: Record<string, Record<string, unknown>>;
      required: string[];
    };
    const submission = schemas["AttemptSubmission"] as {
      properties: Record<string, Record<string, unknown>>;
    };

    expect(Object.keys(verdict.properties).sort()).toEqual(
      ["itemId", "ok", "packRef", "payload"],
    );
    expect([...verdict.required].sort()).toEqual(["ok", "payload"]);
    expect(verdict.properties["itemId"]).toEqual(submission.properties["itemId"]);
    expect(verdict.properties["packRef"]).toEqual(submission.properties["packRef"]);
  });

  it("time on task is bounded, because nothing else bounds it", () => {
    const schemas = (committed["components"] as { schemas: Record<string, Record<string, unknown>> })
      .schemas;
    const submission = schemas["AttemptSubmission"] as {
      properties: Record<string, Record<string, unknown>>;
    };
    const elapsed = submission.properties["elapsedMs"]!;

    expect(elapsed["type"]).toBe("integer");
    expect(elapsed["minimum"]).toBe(0);
    expect(elapsed["maximum"]).toBe(ATTEMPT_ELAPSED_MS_MAX);
    expect(ATTEMPT_ELAPSED_MS_MAX).toBe(3_600_000);
  });

  it("the sweep would catch one", () => {
    const planted = walk({
      components: { schemas: { X: { properties: { templateId: {}, seed: {} } } } },
    });
    const rederivationKey = /^(template_?id|template_?version|seed)$/i;
    const offenders = planted.flatMap(({ path, node }) =>
      path.endsWith("properties") && typeof node === "object" && node !== null
        ? Object.keys(node).filter((n) => rederivationKey.test(n))
        : [],
    );
    expect(offenders.sort()).toEqual(["seed", "templateId"]);
  });
});

/**
 * **The path list is written out rather than derived**, because a path the
 * documents do not name is still a decision. `/packs` joined them on
 * 2026-08-19: `GET /packs/{packId}` fetches by an id and nothing minted one, so
 * `offline_packs` could only ever be empty and a pack attempt could never reach
 * `POST /attempts`.
 *
 * **Every operation declares every error the router can return** — 400, 401,
 * 404 and 405 — because a status the router emits and the contract does not
 * describe is exactly the drift this document exists to prevent. 405 belongs to
 * a *path* rather than to an operation, a request that matched the path and no
 * operation on it, so the conventional spelling declares it on all of them. And
 * each of them is the frozen `Error` shape, not merely present: a 405 declared
 * with no body, or with some other schema, would let the router answer
 * off-contract while this file said it could not.
 *
 * **`operationId`s exist and are distinct** because the hand-written client
 * uses them — ADR 0001 records that the rejected generator discarded them in
 * favour of path-derived names.
 */
describe("every endpoint the documents name is described", () => {
  it("covers the three the client spike measured, the five §5 names, and issuance", () => {
    const paths = Object.keys((committed["paths"] as Record<string, unknown>)).sort();
    expect(paths).toEqual(
      [
        "/attempts",
        "/items/next",
        "/me",
        "/me/history",
        "/me/standing",
        "/packs",
        "/packs/{packId}",
        "/players/link",
      ].sort(),
    );
  });

  it("every operation declares every error the server can return", () => {
    const operations = NODES.filter(
      ({ node }) => typeof node === "object" && node !== null && "responses" in node,
    );
    expect(operations.length).toBeGreaterThan(0);

    for (const { path, node } of operations) {
      const responses = (node as { responses: Record<string, unknown> }).responses;
      for (const status of ["400", "401", "404", "405"]) {
        expect(Object.keys(responses), `\${path} is missing \${status}`).toContain(status);
      }
    }
  });

  it("every error response is the frozen Error shape", () => {
    for (const { node } of NODES) {
      if (typeof node !== "object" || node === null || !("responses" in node)) {
        continue;
      }
      const responses = (node as { responses: Record<string, unknown> }).responses;
      for (const [status, response] of Object.entries(responses)) {
        if (!status.startsWith("4") && !status.startsWith("5")) {
          continue;
        }
        expect(JSON.stringify(response)).toContain(
          '"$ref":"#/components/schemas/Error"',
        );
      }
    }
  });

  it("every operation has an operationId, and they are unique", () => {
    const ids = NODES.flatMap(({ node }) =>
      typeof node === "object" && node !== null && "operationId" in node
        ? [(node as { operationId: string }).operationId]
        : [],
    );
    expect(ids.length).toBeGreaterThan(0);
    expect(new Set(ids).size).toBe(ids.length);
  });
});

/**
 * **Found by sweeping rather than by naming the two schemas**: a third place
 * that grows a band set is exactly the drift this checks for, and a test naming
 * today's two could not see it. Order is pinned as well as membership, because
 * the document is byte-diffed and a set that agrees but reorders is a diff
 * somebody has to read and dismiss.
 */
describe("a player's band is one set, declared once", () => {
  /** Every `enum` in the document that spells a band, with where it was found. */
  const bandEnums = NODES.flatMap(({ path, node }) =>
    typeof node === "object" &&
    node !== null &&
    Array.isArray((node as { enum?: unknown }).enum) &&
    (node as { enum: unknown[] }).enum.includes("under_13")
      ? [{ path, values: (node as { enum: string[] }).enum }]
      : [],
  );

  it("the link request declares one, and so does the profile", () => {
    expect(bandEnums.map(({ path }) => path).sort()).toEqual([
      "components.schemas.Me.properties.ageBand",
      "components.schemas.PlayerLink.properties.ageBand",
    ]);
  });

  it("and they are the same set, in the same order", () => {
    const distinct = new Set(bandEnums.map(({ values }) => JSON.stringify(values)));
    expect(distinct.size).toBe(1);
    expect([...distinct][0]).toBe(JSON.stringify(["under_13", "13_17", "adult"]));
  });
});

/**
 * **One scheme and no second**, so there is no question of which a client
 * should send and no second one to leave half-implemented on the server.
 * `document.ts` carries the rest on the symbols themselves: `SECURITY_SCHEMES`
 * why it is a bearer JWT rather than a cookie, `ROOT_SECURITY` why the
 * requirement is declared once at the root rather than per operation.
 *
 * **Nothing opts out, and that is the thing being caught.** `/health` is not in
 * this document at all — it is an ops route, excused by name in `OPS_ROUTES` —
 * so no operation here should be reachable without a session, and a
 * per-operation `security` override appearing is the drift.
 */
describe("a session travels in the Authorization header", () => {
  const components = (committed as { components: Record<string, unknown> }).components;
  const schemes = (components["securitySchemes"] ?? {}) as Record<
    string,
    { type?: string; scheme?: string; bearerFormat?: string }
  >;

  it("declares exactly one way to authenticate", () => {
    expect(Object.keys(schemes)).toEqual(["session"]);
  });

  it("and it is a bearer JWT, because that is what Neon Auth issues", () => {
    expect(schemes["session"]).toEqual({
      type: "http",
      scheme: "bearer",
      bearerFormat: "JWT",
      description: expect.stringContaining("Neon Auth"),
    });
  });

  it("requires it of everything, by saying so once", () => {
    expect((committed as { security?: unknown }).security).toEqual([{ session: [] }]);
  });

  it("and nothing opts out", () => {
    const overrides = NODES.filter(
      ({ path, node }) =>
        path.startsWith("paths.") &&
        typeof node === "object" &&
        node !== null &&
        "security" in node,
    ).map(({ path }) => path);
    expect(overrides).toEqual([]);
  });
});
