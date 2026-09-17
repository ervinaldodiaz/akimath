import { describe, expect, it } from "vitest";

import { INT64_MAX, INT64_MIN, seedAt } from "../../src/pack/seeds.js";

/**
 * **req-builder-deterministic.** A base that is accepted and then ignored would
 * satisfy every other assertion in this group, so one case moves the base and
 * watches the seed move with it.
 */
describe("a generated item's seed is a counter from a declared base", () => {
  it("is the base for the first item and steps by one", () => {
    expect(seedAt(1000n, 0)).toBe(1000n);
    expect(seedAt(1000n, 1)).toBe(1001n);
    expect(seedAt(1000n, 7)).toBe(1007n);
  });

  it("moves when the base moves", () => {
    expect(seedAt(1000n, 3)).not.toBe(seedAt(2000n, 3));
  });

  it("carries a base far past what a double can hold", () => {
    const big = 9007199254740993n;
    expect(seedAt(big, 2)).toBe(9007199254740995n);
  });

  it("accepts a negative base, because the column is signed", () => {
    expect(seedAt(-5n, 3)).toBe(-2n);
  });
});

/**
 * `issued_items.seed` is a Postgres signed bigint, and the range is checked
 * here because here is where the count is known. A base near the ceiling with a
 * large count wraps in Postgres and silently rederives a different item years
 * later, which is the whole failure mode this package exists to prevent.
 */
describe("a seed that would not fit the column is refused", () => {
  it("refuses a base beyond the signed 64-bit range", () => {
    expect(() => seedAt(INT64_MAX + 1n, 0)).toThrow(/range/);
    expect(() => seedAt(INT64_MIN - 1n, 0)).toThrow(/range/);
  });

  it("refuses a counter that walks off the end", () => {
    expect(seedAt(INT64_MAX - 1n, 1)).toBe(INT64_MAX);
    expect(() => seedAt(INT64_MAX - 1n, 2)).toThrow(/range/);
  });

  it("refuses a negative index", () => {
    expect(() => seedAt(0n, -1)).toThrow();
  });
});
