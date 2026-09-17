import { z } from "zod";

import { DigestSchema } from "./answer.js";

/**
 * What `04 Error` shows a player, carried in a reserved, separately versioned,
 * nullable slot (design.md D3). Q2's answer, decided 2026-08-15: per labelled
 * distractor an `HMAC(canonical answer) → { misconception, steps, explain }`,
 * plus one generic, non-scolding fallback per skill for the answer no
 * distractor anticipated.
 *
 * The distractors are keyed by digest and never by the answer itself: a
 * readable answer per distractor would make the correct one the one *not* in
 * the list, which is the security cost Q2 recorded.
 *
 * `misconception` is an English identifier — it is the id `diag_events`
 * records. `steps` and `explain` are the es-MX copy a player reads (LANG-1).
 */
export const DIAGNOSIS_VERSION = 1 as const;

export const DiagnosisCopySchema = z.strictObject({
  misconception: z.string().regex(/^[a-z][a-z0-9_]*$/u),
  steps: z.array(z.string().min(1)).min(1).max(4),
  explain: z.string().min(1),
});

export type DiagnosisCopy = z.infer<typeof DiagnosisCopySchema>;

export const DiagnosisPayloadSchema = z.strictObject({
  diagnosis_version: z.literal(DIAGNOSIS_VERSION),
  distractors: z
    .array(z.strictObject({ digest: DigestSchema, diagnosis: DiagnosisCopySchema }))
    .min(1),
});

export type DiagnosisPayload = z.infer<typeof DiagnosisPayloadSchema>;

export const SkillFallbackSchema = z.strictObject({
  skill_id: z.int().min(1),
  diagnosis: DiagnosisCopySchema,
});

export type SkillFallback = z.infer<typeof SkillFallbackSchema>;

/**
 * Two entries under one digest make the diagnosis depend on iteration order,
 * and a distractor keyed by the item's own answer puts the correct answer in
 * the list `04 Error` explains away — the exact leak D3 exists to prevent.
 */
export function checkDistractors(
  diagnosis: DiagnosisPayload | null,
  answerDigest: string,
): "duplicate_distractor_digest" | "distractor_matches_answer" | null {
  if (diagnosis === null) {
    return null;
  }
  const seen = new Set<string>();
  for (const distractor of diagnosis.distractors) {
    if (distractor.digest === answerDigest) {
      return "distractor_matches_answer";
    }
    if (seen.has(distractor.digest)) {
      return "duplicate_distractor_digest";
    }
    seen.add(distractor.digest);
  }
  return null;
}

export function fallbackForSkill(
  fallbacks: readonly SkillFallback[],
  skillId: number,
): DiagnosisCopy | null {
  return fallbacks.find((fallback) => fallback.skill_id === skillId)?.diagnosis ?? null;
}

/**
 * The digest of what the player typed in, the diagnosis out. An answer no
 * distractor anticipated resolves to the skill's fallback rather than to
 * nothing — `04` never degrades to "incorrecto".
 */
export function lookupDiagnosis(
  item: { readonly skill_id: number; readonly diagnosis: DiagnosisPayload | null },
  fallbacks: readonly SkillFallback[],
  digest: string,
): DiagnosisCopy | null {
  const labelled: DiagnosisCopy | undefined = item.diagnosis?.distractors.find(
    (distractor) => distractor.digest === digest,
  )?.diagnosis;
  return labelled ?? fallbackForSkill(fallbacks, item.skill_id);
}
