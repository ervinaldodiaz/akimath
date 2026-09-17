import { z } from "zod";

import { API_SCHEMAS } from "./api-schemas.js";
import { toOpenApi303 } from "./downconvert.js";

/**
 * The committed API specification, as a value.
 *
 * **PURE** — no filesystem, no environment, no framework. `ARCHITECTURE.md` §2 is
 * explicit about why that matters: "`packages/contract` exists so the spec can be
 * emitted **without booting Hono or touching `DATABASE_URL`** — if emitting the
 * spec needs a database the CI gate goes flaky and gets disabled."
 *
 * **OpenAPI 3.0.3**, per the same section: Zod emits JSON Schema and no mature
 * Dart generator digests 3.1 well. The gap is closed by `downconvert.ts`, which
 * runs over each schema; the envelope below is assembled around the results.
 *
 * No endpoint here is implemented. This describes what `f3-server-foundation`
 * will serve, which is the point of freezing it first — ADR 0001 makes the Dart
 * client hand-written, so this document is the only thing that can keep it
 * honest.
 */
export const OPENAPI_VERSION = "3.0.3";
export const API_VERSION = "0.1.0";

const ref = (name: keyof typeof API_SCHEMAS): { $ref: string } => ({
  $ref: `#/components/schemas/${name}`,
});

const json = (schema: { $ref: string }): unknown => ({
  content: { "application/json": { schema } },
});

const errors = {
  "400": { description: "The request was malformed.", ...(json(ref("Error")) as object) },
  "401": { description: "No valid session.", ...(json(ref("Error")) as object) },
  "404": { description: "No such resource.", ...(json(ref("Error")) as object) },
  // A response to a request that matched a *path* and no operation on it, so it
  // belongs to none of them and is declared on all of them — the conventional
  // OpenAPI workaround. Declared rather than assumed, because the router
  // returns it and a status the contract does not describe is drift.
  "405": { description: "That method is not routed here.", ...(json(ref("Error")) as object) },
};

/**
 * The answer to a link that cannot happen because one already did.
 *
 * Only `linkPlayer` can produce it: `players.auth_user_id` is UNIQUE and
 * `players.id` is the primary key, so "this account already has a player" and
 * "that player belongs to another account" are the two ways a second link can
 * be refused. Neither is a malformed request and neither is a missing
 * resource, which is why 400 and 404 do not fit.
 */
const alreadyLinked = {
  "409": {
    description: "Already linked — to a different player, or to a different account.",
    ...(json(ref("Error")) as object),
  },
};

/**
 * The answer to an authenticated caller whose operation the server has not
 * built.
 *
 * **Spread per operation, never folded into `errors` above**, because this one
 * is temporary and the others are not. An operation drops the spread in the
 * same diff that builds it, so the diff that implements an endpoint is also the
 * diff that stops advertising it as missing — and
 * `packages/server/test/contract-parity.test.ts` holds this list to exactly the
 * operations the router still answers 501 for, in both directions, so a path
 * that spreads it and a path that does not are both checked rather than
 * asserted, and neither can go stale.
 */
const notImplemented = {
  "501": {
    description: "Routed and authenticated, but the server has not built it yet.",
    ...(json(ref("Error")) as object),
  },
};

/**
 * How a caller proves it has a session.
 *
 * **A bearer JWT, because that is what the provider issues.** ADR 0002 chose
 * Neon Auth; its access token is a JWT signed with EdDSA, verified against the
 * project's JWKS endpoint, and its documented transport is
 * `Authorization: Bearer <jwt>`. Naming the format here rather than leaving the
 * scheme bare is the difference between a client that knows what to send and
 * one that guesses.
 *
 * **Not a cookie**, which is Better Auth's own default. A cookie is a browser
 * mechanism: it needs an origin, it rides along on requests nobody wrote, and
 * the client here is a Flutter app with no browser under it. A header is what a
 * mobile client can actually attach and revoke.
 *
 * One scheme and no second: a document offering two leaves the client asking
 * which and the server implementing whichever it was tested against.
 */
const SECURITY_SCHEMES = {
  session: {
    type: "http",
    scheme: "bearer",
    bearerFormat: "JWT",
    description:
      "A Neon Auth access token. Short-lived — the provider issues 15-minute " +
      "tokens — and verified against the project's JWKS endpoint rather than " +
      "by asking the provider about each request.",
  },
};

const nextItemPath = {
  get: {
    operationId: "getNextItem",
    summary: "The next item to show, already rendered.",
    responses: {
      "200": {
        description: "An item.",
        ...(json(ref("ItemResponse")) as object),
      },
      ...errors,
      ...notImplemented,
    },
  },
};

/**
 * **The rule the schema cannot state.** `AttemptSubmission` carries `itemId`
 * and `packRef` as two optionals because 3.0.3 has no general union and
 * `downconvert.ts` refuses the `oneOf` that would express it. The constraint is
 * real and enforced twice — the server's reader answers 400, the
 * `attempts_one_source` CHECK is behind it — so the operation's `description`
 * states it rather than leaving it to be discovered.
 */
const attemptsPath = {
  post: {
    operationId: "submitAttempts",
    summary: "Submit a session's attempts and receive their verdicts.",
    description:
      "Each attempt names exactly one source: `itemId` for an item this " +
      "server issued, or `packRef` for one the player got in an offline " +
      "pack. Neither, or both, is a 400. The server grades the answer " +
      "itself — there is no field on a submission that asserts a verdict.",
    requestBody: {
      required: true,
      ...(json(ref("AttemptBatch")) as object),
    },
    responses: {
      "200": {
        description: "One verdict per attempt, in the order submitted.",
        ...(json(ref("VerdictBatch")) as object),
      },
      ...errors,
    },
  },
};

/**
 * **The ninth operation, added 2026-08-19.** `GET /packs/{packId}` fetches a
 * pack by an id, and nothing minted one — `offline_packs` could only ever be
 * empty, so `POST /attempts` could never be reached by a pack attempt. This is
 * what mints it.
 *
 * **No request body.** The player comes from the session, the same reason
 * `PlayerLink` refuses an account id: a body that named whose pack to issue
 * would be a caller issuing into somebody else's row. What the pack *contains*
 * is the server's decision, not the client's — difficulty is a rating question
 * and rating is F4.
 *
 * **No `Idempotency-Key`, unlike `POST /players/link`.** Issuing is not
 * idempotent by nature: each call is a new pack, legitimately. A retried
 * request leaves a second pack, and a second pack is harmless — both are valid,
 * both rederive, and the client uses the one it received. Requiring a header
 * the server could not honour would teach clients it means something.
 */
const issuePackPath = {
  post: {
    operationId: "issuePack",
    summary: "Issue a new offline pack to the player.",
    description:
      "Every item in an issued pack is generated from a template, so " +
      "every one can be rederived and graded at sync. Authored content " +
      "and puzzles are not issued this way: they carry no template " +
      "reference, so `(packId, index)` could not address them.",
    responses: {
      "200": { description: "The pack.", ...(json(ref("OfflinePack")) as object) },
      ...errors,
    },
  },
};

/**
 * A re-fetch rebuilds the pack from the stored manifest and salt rather than
 * reading a body back, which is what the manifest is for.
 */
const offlinePackPath = {
  get: {
    operationId: "getOfflinePack",
    summary: "An issued offline pack.",
    parameters: [
      {
        name: "packId",
        in: "path",
        required: true,
        schema: { type: "string", format: "uuid" },
      },
    ],
    responses: {
      "200": {
        description: "The pack.",
        ...(json(ref("OfflinePack")) as object),
      },
      ...errors,
    },
  },
};

const playerLinkPath = {
  post: {
    operationId: "linkPlayer",
    summary: "Attach a locally-minted player to the current account.",
    parameters: [
      {
        name: "Idempotency-Key",
        in: "header",
        required: true,
        schema: { type: "string" },
      },
    ],
    requestBody: {
      required: true,
      ...(json(ref("PlayerLink")) as object),
    },
    responses: {
      "200": { description: "Linked.", ...(json(ref("Me")) as object) },
      ...errors,
      ...alreadyLinked,
    },
  },
};

/**
 * **`DELETE`'s scope is in the contract, not only in the server.** A caller
 * reading `204 Erased.` would reasonably conclude the account is gone too, and
 * it is not: identity lives in the provider's `neon_auth` schema and this
 * service holds no credential that could remove it. Saying so in the
 * operation's `description` is cheaper than a support thread, and it is the one
 * place both halves of the stack read.
 */
const mePath = {
  get: {
    operationId: "getMe",
    summary: "The current player.",
    responses: {
      "200": { description: "The player.", ...(json(ref("Me")) as object) },
      ...errors,
    },
  },
  delete: {
    operationId: "deleteMe",
    summary: "Erase the player and everything this service recorded about them.",
    description:
      "Deletes the player row and everything that references it: attempts, " +
      "issued items, offline packs, skill ratings and diagnosis events. " +
      "Aggregates that carry no player identifier are unaffected. This does " +
      "not delete the Neon Auth account — the email and the sign-in survive " +
      "it, and removing those is a separate act at the identity provider.",
    responses: {
      "204": { description: "Erased." },
      ...errors,
    },
  },
};

/**
 * **What an empty `skills` means, said here rather than inferred.** `rating` is
 * required and not nullable, so unlike `ratingDelta` on a history entry there
 * is no null a caller could read as "not yet" — the absence of a rating is the
 * absence of an entry. The server writes one when a session is rated against a
 * difficulty class the players have already measured, so an empty list means
 * "nobody has measured this player yet" — and a client that drew a 0 from it
 * would be inventing a figure the server never sent.
 */
const standingPath = {
  get: {
    operationId: "getStanding",
    summary: "The player's rating per skill.",
    description:
      "The player's rating for each skill that has one. A skill nothing " +
      "has rated yet has no entry rather than a zero, so a player who has " +
      "never been rated is answered an empty list and not a 404. This " +
      "operation carries rating only: accuracy and time on task are not " +
      "part of this shape.",
    responses: {
      "200": {
        description: "The standing.",
        ...(json(ref("Standing")) as object),
      },
      ...errors,
    },
  },
};

const historyPath = {
  get: {
    operationId: "getHistory",
    summary: "Recent series and puzzles.",
    responses: {
      "200": {
        description: "The history.",
        ...(json(ref("History")) as object),
      },
      ...errors,
    },
  },
};

/**
 * **At the root, not per operation.** Every operation in this document is
 * client-facing and every one of them declares `401 — No valid session`, so
 * repeating the requirement eight times buys nothing and costs the ninth, where
 * somebody forgets the line and ships an open endpoint. `/health` is not here
 * to be excused: it is an ops route, named in `OPS_ROUTES` and deliberately
 * outside the contract.
 */
const ROOT_SECURITY = [{ session: [] }];

/** Every path this service describes, in the order the document declares them. */
const PATHS = {
  "/items/next": nextItemPath,
  "/attempts": attemptsPath,
  "/packs": issuePackPath,
  "/packs/{packId}": offlinePackPath,
  "/players/link": playerLinkPath,
  "/me": mePath,
  "/me/standing": standingPath,
  "/me/history": historyPath,
};

export function buildOpenApiDocument(): unknown {
  const schemas: Record<string, unknown> = {};
  for (const [name, schema] of Object.entries(API_SCHEMAS)) {
    schemas[name] = toOpenApi303(
      z.toJSONSchema(schema as z.ZodType, { target: "draft-7" }),
    );
  }

  return {
    openapi: OPENAPI_VERSION,
    info: {
      title: "AkiMath API",
      version: API_VERSION,
      description:
        "The prompt travels rendered. The answer never travels online. Offline, " +
        "a membership verifier travels and its verdict is provisional until sync.",
    },
    servers: [{ url: "/v1" }],
    paths: PATHS,
    security: ROOT_SECURITY,
    components: { schemas, securitySchemes: SECURITY_SCHEMES },
  };
}
