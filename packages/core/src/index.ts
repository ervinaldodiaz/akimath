/**
 * `@akimath/core` — the rederivation machine.
 *
 * Re-export only, no logic: the precedent `packages/contract`'s own index sets,
 * and it is what lets `test/public_surface.test.ts` assert the whole public
 * surface in one place.
 *
 * Zero runtime dependencies, enforced by reading the manifest
 * (`test/dependency-allowlist.test.ts`), and no ambient IO, enforced by walking
 * the AST (`test/determinism.test.ts`).
 *
 * **Why the rating engine is exported from here at all.**
 * `packages/server` runs it inside the sync transaction — `ARCHITECTURE.md` §5
 * puts the Glicko computation between the INSERT's `RETURNING` and the
 * `user_skills` upsert — so the engine has to cross the package boundary. It
 * lives here rather than there because this package is the one allowed
 * `Math.exp` (§3), and because a second transcription of Glickman's formulas is
 * exactly the drift R2 names, against a module whose golden vector is his own
 * worked example. That covers both `decay` and the `rating/glicko.js` group
 * below.
 */
export {
  abs,
  add,
  compare,
  divide,
  equals,
  isInteger,
  multiply,
  negate,
  rationalOf,
  reciprocal,
  signOf,
  subtract,
  type Rational,
} from "./rational.js";

export {
  drawBelow,
  intBetween,
  mix64,
  rejectionLimit,
  wordAt,
  type WordSource,
} from "./prng/splitmix64.js";

export {
  issuable,
  rederive,
  registryOf,
  resolve,
  type TemplateRegistry,
} from "./registry.js";

export { coreRegistry } from "./templates/index.js";

export {
  fromManifestEntry,
  templateRefOf,
  toDigestEntry,
  toManifestEntry,
  type DigestManifestEntry,
  type ManifestEntry,
  type TemplateManifestEntry,
} from "./manifest.js";

/**
 * `FALLBACK_MISCONCEPTION` stays internal on purpose: it is a string, and every
 * export here is a function so that nothing crossing the boundary can grow a
 * `toString`. A caller wants the copy, not the key that finds it.
 */
export { fallbackDiagnosis, misconceptionCopy } from "./pack/misconceptions.js";

export { skillName } from "./pack/skill-names.js";

export { decay } from "./rating/decay.js";
export {
  initialSkill,
  rateSession,
  type Outcome,
  type Skill,
} from "./rating/glicko.js";

export type {
  GeneratedItem,
  PromptToken,
  Template,
  TemplateRef,
  Term,
} from "./template.js";
