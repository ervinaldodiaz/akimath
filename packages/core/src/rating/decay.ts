import { INITIAL_DEVIATION, type Skill } from "./glicko.js";

/**
 * How uncertain a rating becomes while nobody is playing.
 *
 * Glickman's Step 1: `RD = min(√(RD_old² + c²), 350)`, where `c` governs how
 * fast uncertainty grows between rating periods.
 *
 * **In days, not in periods.** `ARCHITECTURE.md` §3 is explicit —
 * "`decay(prior, elapsedDays)` operates in **days**, or an inactive user never
 * decays". With the session as the rating period, a child who does not open the
 * app has no periods at all, so a per-period decay would leave a year-old rating
 * looking as certain as yesterday's. Variance grows linearly with time, so the
 * day count multiplies `c²` rather than the number of sessions.
 */

/**
 * `c²` per day, chosen so a well-measured rating (RD 50) returns to the unrated
 * RD of 350 after a year away.
 *
 * A year is the judgement call in this file, and it is written as an equation
 * rather than a magic number so the choice is visible: change `DAYS_TO_UNRATED`
 * and the constant follows.
 */
const WELL_MEASURED_DEVIATION = 50;
const DAYS_TO_UNRATED = 365;
const C_SQUARED_PER_DAY =
  (INITIAL_DEVIATION * INITIAL_DEVIATION -
    WELL_MEASURED_DEVIATION * WELL_MEASURED_DEVIATION) /
  DAYS_TO_UNRATED;

/**
 * The prior, aged by `elapsedDays`. The rating never moves — only certainty
 * about it does.
 *
 * **Growth is capped at the unrated deviation**: past that, the system knows
 * nothing about the player and there is nothing further to forget.
 */
export function decay(prior: Skill, elapsedDays: number): Skill {
  if (!Number.isFinite(elapsedDays) || elapsedDays < 0) {
    throw new RangeError(`elapsed days must be zero or more: ${elapsedDays}`);
  }
  if (elapsedDays === 0) {
    return prior;
  }

  const grown = Math.sqrt(
    prior.deviation * prior.deviation + C_SQUARED_PER_DAY * elapsedDays,
  );

  return Object.freeze({
    rating: Math.fround(prior.rating),
    deviation: Math.fround(Math.min(grown, INITIAL_DEVIATION)),
  });
}
