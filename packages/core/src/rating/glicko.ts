/**
 * Glicko-1, with the session as the rating period.
 *
 * Every formula and every constant is transcribed from Mark Glickman's "The
 * Glicko system", <https://www.glicko.net/glicko/glicko.pdf>, fetched
 * 2026-08-17, and his worked example on page 4 is the anchor in
 * `test/rating/glicko.test.ts`. Nothing here was recalled: a wrong constant in a
 * rating produces plausible numbers forever, which is worse than a crash.
 *
 * **Glicko-1 and not Glicko-2**, decided by the schema rather than by taste:
 * `user_skills` is `(player_id, skill_id, rating real, deviation real,
 * updated_at)` and carries no volatility column, which Glicko-2 requires.
 *
 * **The rating period is the session.** `ARCHITECTURE.md` §3: grouping by
 * request is deterministic but not *consistent* — two children with identical
 * play would get different ratings depending on whether they had a connection,
 * in the app whose promise is fair adaptive difficulty. A session arrives as a
 * batch and is rated as one period.
 */

/** `ln(10)/400`. Glickman writes it as 0.0057565; this is the exact form. */
const Q = Math.log(10) / 400;

/** A player's strength, exactly as the schema stores it. */
export interface Skill {
  readonly rating: number;
  readonly deviation: number;
}

/**
 * One graded item, against an opponent whose strength the caller supplies.
 *
 * **Core decides nothing about where an opponent rating comes from**, and this
 * module is correct under any provenance. `packages/server/src/rating.ts` is
 * where the decision was taken: the opponent is the difficulty class
 * `(skill_id, ladder_step)`, whose rating is *measured* by feeding the mirrored
 * outcome back through this same function. `ladder_step` names the class and
 * never sets its worth — it is a label, not a rating, which is why it is not
 * mapped onto this scale.
 */
export interface Outcome {
  readonly opponentRating: number;
  readonly opponentDeviation: number;
  /** 1 for a win, 0.5 for a draw, 0 for a loss. */
  readonly score: number;
}

/** Glickman's defaults for a player nobody has seen yet. */
export const INITIAL_RATING = 1500;
export const INITIAL_DEVIATION = 350;

/**
 * The prior for something this system has never rated.
 *
 * **A function, because the package's front door exports only functions** —
 * `test/public_surface.test.ts` asserts it, so that nothing crossing the
 * boundary can grow a `toString`. The two constants above stay module-level for
 * `decay`, which needs the ceiling rather than the pair.
 *
 * **Frozen, like every other value this module returns.** A caller that mutated
 * the prior would be mutating the default for the next one.
 */
export function initialSkill(): Skill {
  return Object.freeze({ rating: INITIAL_RATING, deviation: INITIAL_DEVIATION });
}

/** `g(RD)` — how much an opponent's uncertainty damps the update. */
function g(deviation: number): number {
  return 1 / Math.sqrt(1 + (3 * Q * Q * deviation * deviation) / (Math.PI * Math.PI));
}

/** `E(s|r, rj, RDj)` — the expected score against one opponent. */
function expected(rating: number, outcome: Outcome): number {
  return (
    1 /
    (1 +
      Math.pow(
        10,
        (-g(outcome.opponentDeviation) * (rating - outcome.opponentRating)) / 400,
      ))
  );
}

/**
 * The player's strength after one rating period.
 *
 * **Narrowed to float32 on the way out**, because that is what `user_skills`
 * stores. It is also what makes the committed rating fixture byte-exact:
 * `Math.exp`, `Math.log` and `Math.pow` are implementation-approximated, so this
 * cannot be bit-identical across engines the way BigInt arithmetic is — but
 * float32 is coarse enough to absorb far more error than an engine introduces,
 * and the test measures that margin rather than asserting it.
 *
 * The mechanism is worth stating precisely so it is not misapplied: this works
 * because the *stored* type is narrower than the *computed* one. It is not a
 * general licence to call floating point deterministic.
 *
 * **An empty period returns the prior untouched.** No outcomes is not a loss:
 * Glickman's RD growth comes from time passing, which is `decay`'s job, not
 * from a period nobody played.
 *
 * `dSquared` is Glickman's `d²`, the variance of the period's evidence, and
 * `weight` combines it with the prior's own.
 */
export function rateSession(prior: Skill, outcomes: readonly Outcome[]): Skill {
  if (outcomes.length === 0) {
    return prior;
  }

  let informationSum = 0;
  let scoreSum = 0;

  for (const outcome of outcomes) {
    const gj = g(outcome.opponentDeviation);
    const ej = expected(prior.rating, outcome);
    informationSum += gj * gj * ej * (1 - ej);
    scoreSum += gj * (outcome.score - ej);
  }

  const dSquared = 1 / (Q * Q * informationSum);
  const weight = 1 / (1 / (prior.deviation * prior.deviation) + 1 / dSquared);

  return Object.freeze({
    rating: Math.fround(prior.rating + Q * weight * scoreSum),
    deviation: Math.fround(Math.sqrt(weight)),
  });
}
