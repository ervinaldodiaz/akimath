import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { answerDigest } from "../src/digest.js";
import {
  buildDigestGolden,
  DIGEST_GOLDEN_SALT,
  DIGEST_INPUTS,
} from "../src/digest-vectors.js";

/**
 * The parity table the **digest** is measured against, across two stacks.
 *
 * `canon.golden.json` pins how an answer is spelled and nothing pins what it
 * hashes to. That gap does not matter while only TypeScript computes a digest,
 * and it becomes R2 the moment Dart does — which is what reading an issued pack
 * offline requires. So the fixture is emitted now, before the second
 * implementation exists, and the second implementation is written against it.
 *
 * **Two cross-stack mistakes it is shaped to catch.** The salt is *hex* and is
 * decoded to bytes before it is used as a key — an implementation that keys on
 * the hex characters produces a plausible digest that matches nothing. And the
 * message is the canonical answer's UTF-8 bytes and nothing else: no length
 * prefix, no separator, no trailing newline.
 */
function readFixture(name: string): unknown {
  return JSON.parse(
    readFileSync(
      fileURLToPath(new URL(`../../../contract/fixtures/${name}`, import.meta.url)),
      "utf8",
    ),
  ) as unknown;
}

/**
 * **A table where everything collided would pass every other assertion here**,
 * which is why one case pins that it does not. `2/4` and `1/2` are one value
 * and one canonical spelling, so they share a digest — that is the point of
 * canonicalizing first — and `1/2` and `1/3` do not.
 */
describe("the digest golden", () => {
  it("is what the code produces, not a hand-written vector", () => {
    expect(readFixture("digest.golden.json")).toEqual(
      JSON.parse(JSON.stringify(buildDigestGolden())),
    );
  });

  it("covers every input, and there is at least one", () => {
    const golden = buildDigestGolden();
    expect(DIGEST_INPUTS.length).toBeGreaterThan(0);
    expect(golden.vectors).toHaveLength(DIGEST_INPUTS.length);
  });

  it("publishes the salt it keyed on, because a digest without one is unrepeatable", () => {
    const golden = buildDigestGolden();
    expect(golden.pack_salt_hex).toBe(DIGEST_GOLDEN_SALT);
    expect(DIGEST_GOLDEN_SALT).toMatch(/^[0-9a-f]{64}$/);
  });

  it("keys on the salt's bytes, not on its hex characters", () => {
    const asBytes = answerDigest(DIGEST_GOLDEN_SALT, "7");
    const asCharacters = answerDigest(
      Buffer.from(DIGEST_GOLDEN_SALT, "utf8").toString("hex"),
      "7",
    );
    expect(asBytes).not.toBe(asCharacters);
  });

  it("hashes the message with no length prefix, separator or trailing newline", () => {
    const plain = answerDigest(DIGEST_GOLDEN_SALT, "1/2");
    expect(plain).not.toBe(answerDigest(DIGEST_GOLDEN_SALT, "1/2\n"));
    expect(plain).not.toBe(answerDigest(DIGEST_GOLDEN_SALT, "3:1/2"));
  });

  it("gives every vector a lowercase, untruncated hex digest", () => {
    for (const vector of buildDigestGolden().vectors) {
      expect(vector.digest).toMatch(/^[0-9a-f]{64}$/);
    }
  });

  it("distinguishes answers that canonicalize apart", () => {
    const digests = buildDigestGolden().vectors.map((v) => v.digest);
    expect(new Set(digests).size).toBeGreaterThan(1);
  });
});
