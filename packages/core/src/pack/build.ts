import {
  answerDigest,
  parsePack,
  storedAnswer,
  type DiagnosisCopy,
  type Item,
  type Pack,
} from "@akimath/contract";

import { rederive, resolve, type TemplateRegistry } from "../registry.js";
import type { Declaration } from "./declaration.js";
import { predictDistractors } from "./distractors.js";
import { liftAuthored, readAuthoredFile } from "./lift.js";
import { readPuzzleFile } from "./puzzles.js";
import { seedAt } from "./seeds.js";

/**
 * A declaration and a registry in, a pack out.
 *
 * **PURE** — reading the authored files is injected, so the whole assembly is
 * testable without a filesystem and the CLI beside it decides nothing.
 *
 * **A pack is assembled from sources**, in the order they are declared, and a
 * source is either a template invocation or an authored file. That is the shape
 * that lets this exist at all: `packages/core` ships one template and the app
 * draws six families, so a wholly generated pack would take a player from six
 * kinds of question to one. Sources make the five authored families
 * first-class rather than a migration step, and turn "add a template" into an
 * edit to a declaration.
 */

export interface BuildInputs {
  readonly registry: TemplateRegistry;
  /** Resolves a source's declared path to its contents. */
  readonly readAuthored: (path: string) => string;
  /**
   * The copy shown when a wrong answer matches no distractor, per skill.
   *
   * Required rather than defaulted: the frozen validator refuses an item whose
   * skill has no fallback, and inventing a placeholder here would ship "TODO"
   * to a player. A skill with nothing to say fails the build instead.
   */
  readonly fallbacks: ReadonlyMap<number, DiagnosisCopy>;
  /**
   * Copy for each misconception a distractor can name.
   *
   * A distractor naming a misconception this does not hold fails the build. The
   * alternative — emitting the distractor with no copy — is an item that
   * recognises a mistake and then has nothing to say about it, which is worse
   * than not recognising it.
   */
  readonly misconceptions: ReadonlyMap<string, DiagnosisCopy>;
}

/** What was built, beside the pack — so a build can report rather than assert. */
export interface BuildReport {
  readonly generated: number;
  readonly authored: number;
  readonly diagnosed: number;
  readonly byFamily: ReadonlyMap<string, number>;
  /** Which puzzles were carried, so an empty list is visible not assumed. */
  readonly puzzleKinds: readonly string[];
}

export interface BuildResult {
  readonly pack: Pack;
  readonly report: BuildReport;
}

/**
 * One generated item, in the frozen envelope.
 *
 * **One resolve, two answers.** The template both generates the item and says
 * which skill it exercises; asking the registry twice would let a future
 * `rederive` and a future `resolve` disagree about which version answered.
 *
 * The template carries an exact `Rational` and never a string, because
 * rendering belongs to the contract — which already owns what `5/4` looks
 * like and is checked against Dart on the same fixture.
 *
 * **The shape and the spelling are one decision, and used to be two here.**
 * This computed them separately and the spelling always carried a
 * denominator, so a whole answer of −9 was digested as `-9/1` while
 * `answer.shape` said `integer`. `storedAnswer` is now that decision, in
 * `packages/contract`, because the two other producers — `lift.ts` beside
 * this file, and the server grading a rederived item — have to make the same
 * one. Held by `test/one-way-to-spell-an-answer.test.ts`.
 */
function fromTemplate(
  declaration: Declaration,
  registry: TemplateRegistry,
  source: Extract<Declaration["sources"][number], { kind: "template" }>,
  seedIndex: number,
  misconceptions: ReadonlyMap<string, DiagnosisCopy>,
): Item {
  const template = resolve(registry, source);
  const generated = template.generate({
    templateId: source.templateId,
    templateVersion: source.templateVersion,
    seed: seedAt(declaration.seedBase, seedIndex),
    ladderStep: source.ladderStep,
  });

  const { shape, canonical } = storedAnswer(
    generated.answer.numerator,
    generated.answer.denominator,
  );

  return {
    skill_id: template.skillId,
    ladder_step: generated.ladderStep,
    keypad: "item",
    stimulus: {
      kind: "arithmetic",
      payload: {
        operator: generated.operator,
        left: generated.left,
        right: generated.right,
      },
    } as Item["stimulus"],
    answer: {
      shape,
      digest: answerDigest(declaration.packSalt, canonical),
    },
    diagnosis: diagnosisFor(generated, canonical, declaration.packSalt, misconceptions),
  };
}

/**
 * The distractors an item carries, or null when its family has no rules yet.
 *
 * Null rather than an empty list: the frozen `DiagnosisPayloadSchema` requires
 * at least one distractor, so "none predicted" and "some predicted" are
 * genuinely different shapes.
 */
function diagnosisFor(
  generated: ReturnType<typeof rederive>,
  canonical: string,
  packSalt: string,
  misconceptions: ReadonlyMap<string, DiagnosisCopy>,
): Item["diagnosis"] {
  const predicted = predictDistractors(generated, canonical);
  if (predicted.length === 0) {
    return null;
  }
  return {
    diagnosis_version: 1,
    distractors: predicted.map((distractor) => {
      const copy = misconceptions.get(distractor.misconception);
      if (copy === undefined) {
        throw new TypeError(
          `no copy for misconception "${distractor.misconception}"; an item that ` +
            `recognises a mistake and cannot explain it is worse than one that does not`,
        );
      }
      return { digest: answerDigest(packSalt, distractor.answer), diagnosis: copy };
    }),
  } as Item["diagnosis"];
}

/**
 * The declared sources, assembled in order into one validated pack.
 *
 * **The seed counter spans the whole build, not each source**, so two template
 * sources never issue the same seed. `generated` is that counter and the
 * figure the report carries, which is one fact read twice rather than two.
 *
 * **Puzzles are carried through as authored, not transformed**: the frozen
 * envelope is what the file already holds, and rewriting it here would be a
 * second opinion about a format this package does not own.
 *
 * **Every skill an item names is declared available.** The lattice that
 * decides what is locked is the skill map's, at F5; a pack that declared
 * everything locked would be a pack with nothing to play.
 *
 * **Validated here, before anything is written.** The CLI cannot be the only
 * place this happens: a caller that assembled a pack and skipped the check
 * would produce something no reader accepts, and the failure would surface on
 * a device rather than in a build.
 */
export function buildPack(
  declaration: Declaration,
  inputs: BuildInputs,
): BuildResult {
  const items: Item[] = [];
  const puzzles: Pack["puzzles"] = [];
  let generated = 0;
  let authored = 0;

  for (const source of declaration.sources) {
    if (source.kind === "template") {
      for (let n = 0; n < source.count; n += 1) {
        items.push(
          fromTemplate(declaration, inputs.registry, source, generated, inputs.misconceptions),
        );
        generated += 1;
      }
      continue;
    }
    if (source.kind === "puzzles") {
      for (const puzzle of readPuzzleFile(inputs.readAuthored(source.path))) {
        puzzles.push(puzzle);
      }
      continue;
    }
    for (const raw of readAuthoredFile(inputs.readAuthored(source.path))) {
      items.push(
        liftAuthored(raw, { skillId: source.skillId, packSalt: declaration.packSalt }),
      );
      authored += 1;
    }
  }

  const skillIds = [...new Set(items.map((item) => item.skill_id))].sort((a, b) => a - b);
  for (const skillId of skillIds) {
    if (!inputs.fallbacks.has(skillId)) {
      throw new TypeError(
        `skill ${skillId} has items but no fallback copy; a wrong answer there ` +
          `would be met with silence`,
      );
    }
  }

  const pack: Pack = {
    pack_format_version: 1,
    pack_salt: declaration.packSalt,
    issued_at: declaration.issuedAt,
    expires_at: declaration.expiresAt,
    skill_nodes: skillIds.map((skill_id) => ({ skill_id, state: "available" as const })),
    skill_fallbacks: skillIds.map((skill_id) => ({
      skill_id,
      diagnosis: inputs.fallbacks.get(skill_id) as DiagnosisCopy,
    })),
    items,
    puzzles,
  };

  const verdict = parsePack(pack);
  if (!verdict.ok) {
    throw new TypeError(`the assembled pack is not valid: ${verdict.tag}`);
  }

  const byFamily = new Map<string, number>();
  for (const item of items) {
    const kind = item.stimulus.kind;
    byFamily.set(kind, (byFamily.get(kind) ?? 0) + 1);
  }

  return {
    pack: verdict.pack,
    report: {
      generated,
      authored,
      diagnosed: items.filter((item) => item.diagnosis !== null).length,
      byFamily,
      puzzleKinds: puzzles.map((puzzle) => puzzle.kind),
    },
  };
}
