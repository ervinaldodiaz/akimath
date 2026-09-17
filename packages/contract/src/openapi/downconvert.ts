/**
 * JSON Schema (as Zod emits it) → the subset OpenAPI 3.0.3 admits.
 *
 * `ARCHITECTURE.md` §2 pins 3.0.3 and not 3.1: "Zod 4 emits JSON Schema 2020-12
 * which maps to 3.1, and no mature Dart generator digests that well." Zod's
 * `draft-7` target gets closest, and this closes the remaining gap.
 *
 * **PURE.** A document in, a document out; no IO, no clock, nothing ambient. The
 * hardest part of the emitter is therefore tested without emitting a file.
 *
 * **It refuses what it does not recognise.** A pass-through default is how a
 * later-dialect construct reaches a Dart client that cannot read it, months
 * afterwards, with every gate green the whole way — and ADR 0001 makes that
 * client hand-written, so no generator would trip over it first. The vocabulary
 * below is closed on purpose and grows deliberately.
 */

/** Keywords 3.0.3 admits unchanged. Exported so every entry can be exercised. */
export const CARRIED_THROUGH: ReadonlySet<string> = new Set([
  "type",
  "properties",
  "required",
  "items",
  "enum",
  "format",
  "pattern",
  "minimum",
  "maximum",
  "minLength",
  "maxLength",
  "minItems",
  "maxItems",
  "uniqueItems",
  "additionalProperties",
  "description",
  "title",
  "default",
  "nullable",
  "deprecated",
  "readOnly",
  "writeOnly",
  "example",
  "$ref",
]);

/**
 * Keywords whose value is a **map of schemas keyed by arbitrary names**, not a
 * schema itself. Their children are names — `properties.itemId` is a field, not
 * a keyword — so the vocabulary check must not run on them.
 *
 * The first walk did run on them, and rejected every field in every schema as
 * an unknown keyword. It is the obvious bug and it is also the reason this
 * module converts *schemas* rather than whole documents: teaching it OpenAPI's
 * object model — paths, responses, media types — would make it a second,
 * weaker parser of a specification it does not own.
 */
const NAME_KEYED: ReadonlySet<string> = new Set(["properties"]);

/**
 * Keywords dropped outright rather than translated.
 *
 * `$schema` says "this is JSON Schema", which a 3.0.3 document is not.
 * `propertyNames` is what Zod emits for `z.record(z.string(), …)`, where it says
 * only "the keys are strings" — which JSON already guarantees — and 3.0.3 has
 * no such keyword to say it with anyway.
 */
const DROPPED: ReadonlySet<string> = new Set(["$schema", "propertyNames"]);

/** Keywords this converter rewrites. Anything else is an error. */
export const REWRITTEN: ReadonlySet<string> = new Set([
  "$schema",
  "const",
  "anyOf",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "propertyNames",
]);

/**
 * The bounds Zod adds to an unbounded integer.
 *
 * `z.int()` emits ±9007199254740991 — JavaScript's safe-integer range. That is a
 * fact about the emitter's host language, not about the API, and publishing it
 * would make every client honour a limit nobody chose.
 */
const JS_SAFE_MAX = 9007199254740991;
const JS_SAFE_MIN = -9007199254740991;

type Json = Record<string, unknown>;

const isObject = (value: unknown): value is Json =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function fail(keyword: string, path: string): never {
  throw new Error(
    `openapi 3.0.3 has no \`${keyword}\` (at ${path || "<root>"}). ` +
      "Add a conversion for it in downconvert.ts, or express the schema " +
      "differently — it must not reach the document unconverted.",
  );
}

/**
 * `anyOf: [X, {type: "null"}]` is Zod's nullable. 3.0.3 spells it as a keyword
 * on the non-null branch, and has no general union in a response at all
 * (`ARCHITECTURE.md` §2: zero response polymorphism).
 */
function nullableUnion(branches: readonly unknown[]): Json | undefined {
  if (branches.length !== 2) {
    return undefined;
  }
  const nulls = branches.filter((b) => isObject(b) && b["type"] === "null");
  const rest = branches.filter((b) => !(isObject(b) && b["type"] === "null"));
  if (nulls.length !== 1 || rest.length !== 1 || !isObject(rest[0])) {
    return undefined;
  }
  return { ...rest[0], nullable: true };
}

/**
 * `anyOf` replaces the **whole node** rather than one of its keys, which is why
 * it is collapsed before the per-keyword walk rather than inside it.
 */
function collapsedAnyOf(node: Json, anyOf: readonly unknown[], path: string): Json {
  const collapsed = nullableUnion(anyOf);
  if (collapsed === undefined) {
    fail("anyOf", path);
  }
  const { anyOf: _dropped, ...rest } = node;
  return { ...rest, ...collapsed };
}

/**
 * One half of the ±safe-integer pair Zod puts on an unbounded `z.int()`.
 *
 * Recognised as a **pair** — both bounds present, on an integer — so a schema
 * that really does say `max(9007199254740991)` beside a real minimum keeps it.
 */
function isSyntheticIntegerBound(key: string, value: unknown, node: Json): boolean {
  if (node["type"] !== "integer") {
    return false;
  }
  if (node["minimum"] !== JS_SAFE_MIN || node["maximum"] !== JS_SAFE_MAX) {
    return false;
  }
  return (
    (key === "maximum" && value === JS_SAFE_MAX) ||
    (key === "minimum" && value === JS_SAFE_MIN)
  );
}

function convertNode(node: unknown, path: string): unknown {
  if (Array.isArray(node)) {
    return node.map((item, index) => convertNode(item, `${path}[${index}]`));
  }
  if (!isObject(node)) {
    return node;
  }

  const anyOf = node["anyOf"];
  if (Array.isArray(anyOf)) {
    return convertNode(collapsedAnyOf(node, anyOf, path), path);
  }

  const out: Json = {};

  for (const [key, value] of Object.entries(node)) {
    const where = path === "" ? key : `${path}.${key}`;

    if (DROPPED.has(key)) {
      continue;
    }

    if (key === "const") {
      out["enum"] = [value];
      continue;
    }

    if (key === "exclusiveMinimum" || key === "exclusiveMaximum") {
      const alreadyInBooleanForm = typeof value !== "number";
      if (alreadyInBooleanForm) {
        out[key] = value;
        continue;
      }
      out[key === "exclusiveMinimum" ? "minimum" : "maximum"] = value;
      out[key] = true;
      continue;
    }

    if (key === "type" && Array.isArray(value)) {
      const withoutNull = value.filter((t) => t !== "null");
      if (withoutNull.length !== 1 || value.length !== 2) {
        fail("type (as an array)", where);
      }
      out["type"] = withoutNull[0];
      out["nullable"] = true;
      continue;
    }

    if (isSyntheticIntegerBound(key, value, node)) {
      continue;
    }

    if (!CARRIED_THROUGH.has(key) && !REWRITTEN.has(key)) {
      fail(key, where);
    }

    if (NAME_KEYED.has(key)) {
      if (!isObject(value)) {
        fail(key, where);
      }
      const converted: Json = {};
      for (const [name, child] of Object.entries(value)) {
        converted[name] = convertNode(child, `${where}.${name}`);
      }
      out[key] = converted;
      continue;
    }

    out[key] = convertNode(value, where);
  }

  return out;
}

/**
 * One JSON **schema**, in the dialect 3.0.3 admits.
 *
 * Deliberately not "one document": the OpenAPI envelope — paths, operations,
 * responses, media types — is assembled by `document.ts` around schemas this has
 * already converted. A converter that also walked the envelope would be a second
 * parser of a specification it does not own, and its vocabulary check would have
 * to admit every OpenAPI keyword to avoid firing on them, which is precisely how
 * a real unknown keyword would get waved through.
 */
export function toOpenApi303(schema: unknown): unknown {
  return convertNode(schema, "");
}
