import { describe, expect, it } from "vitest";

import { decay } from "../../src/rating/decay.js";
import { INITIAL_DEVIATION, type Skill } from "../../src/rating/glicko.js";

/**
 * Uncertainty is counted in days away, never in sessions.
 *
 * With the session as the rating period, a player who never opens the app has
 * no periods at all, so a per-period decay would leave a year-old rating
 * looking as certain as yesterday's. Counting days is what makes an absence
 * cost something.
 */

/** A rating the system is very sure of, so an absence has room to blunt it. */
const sharp: Skill = { rating: 1600, deviation: 50 };

describe("uncertainty grows with days away, not with sessions", () => {
  it("zero days changes nothing at all", () => {
    expect(decay(sharp, 0)).toEqual(sharp);
  });

  it("the rating itself never moves — time says only how sure you can be, and nudging it would invent evidence", () => {
    for (const days of [1, 30, 365, 5000]) {
      expect(decay(sharp, days).rating).toBe(sharp.rating);
    }
  });

  it("more days means more uncertainty, monotonically", () => {
    let previous = sharp.deviation;
    for (const days of [1, 7, 30, 90, 200]) {
      const grown = decay(sharp, days).deviation;
      expect(grown, `${days} days`).toBeGreaterThan(previous);
      previous = grown;
    }
  });

  it("a well-measured rating reaches the unrated deviation after a year, which is decay.ts's judgement call pinned", () => {
    expect(decay(sharp, 365).deviation).toBeCloseTo(INITIAL_DEVIATION, 0);
  });

  it("and never exceeds it, however long the absence, because there is nothing further to forget", () => {
    for (const days of [400, 1000, 100_000]) {
      expect(decay(sharp, days).deviation).toBe(INITIAL_DEVIATION);
    }
  });

  it("an inactive player does decay — the whole point of counting days", () => {
    expect(decay(sharp, 365).deviation).toBeGreaterThan(sharp.deviation * 6);
  });

  it("refuses a negative or non-finite span", () => {
    expect(() => decay(sharp, -1)).toThrow(/zero or more/);
    expect(() => decay(sharp, Number.NaN)).toThrow(/zero or more/);
    expect(() => decay(sharp, Number.POSITIVE_INFINITY)).toThrow(/zero or more/);
  });

  it("is narrowed to what the schema stores", () => {
    const aged = decay(sharp, 42);
    expect(Math.fround(aged.deviation)).toBe(aged.deviation);
    expect(Math.fround(aged.rating)).toBe(aged.rating);
  });

  it("a fractional day is not rounded away, or a player returning twice a day would never decay", () => {
    expect(decay(sharp, 0.5).deviation).toBeGreaterThan(sharp.deviation);
    expect(decay(sharp, 0.5).deviation).toBeLessThan(decay(sharp, 1).deviation);
  });
});
