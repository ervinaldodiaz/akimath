import { rederive } from "./registry.js";
import type { TemplateRef } from "./template.js";
import { CORE_REGISTRY } from "./templates/index.js";

/**
 * Every template version, generating at a fixed ladder of seeds.
 *
 * The artifact this produces is what makes a behaviour change to an existing
 * version impossible to land quietly: a version is frozen history, so any diff
 * here on an existing row is a defect rather than an update.
 */
/**
 * Seeds spanning the signed range, including both extremes.
 *
 * `389n` is not an arbitrary middle value: it is the seed that reproduces the
 * shipped `sub-2`.
 */
export const SEED_LADDER: readonly bigint[] = [
  0n,
  1n,
  389n,
  9223372036854775807n,
  -9223372036854775808n,
];

const LADDER_STEPS: readonly number[] = [1, 2, 3, 5];

export interface TemplateGoldenRow {
  readonly templateId: string;
  readonly templateVersion: number;
  readonly seed: string;
  readonly ladderStep: number;
  readonly prompt: readonly unknown[];
  readonly answer: { readonly numerator: string; readonly denominator: string };
}

export interface TemplateGolden {
  readonly rows: readonly TemplateGoldenRow[];
}

export function buildTemplateGolden(): TemplateGolden {
  const rows: TemplateGoldenRow[] = [];

  for (const template of CORE_REGISTRY.byKey.values()) {
    for (const seed of SEED_LADDER) {
      for (const ladderStep of LADDER_STEPS) {
        const ref: TemplateRef = {
          templateId: template.id,
          templateVersion: template.version,
          seed,
          ladderStep,
        };
        const item = rederive(CORE_REGISTRY, ref);
        rows.push({
          templateId: ref.templateId,
          templateVersion: ref.templateVersion,
          seed: seed.toString(),
          ladderStep,
          prompt: item.prompt,
          answer: {
            numerator: item.answer.numerator.toString(),
            denominator: item.answer.denominator.toString(),
          },
        });
      }
    }
  }

  return { rows };
}
