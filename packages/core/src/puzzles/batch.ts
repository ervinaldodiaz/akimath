import { parsePuzzle, type PuzzleEnvelope, type PuzzleRejectionTag } from "@akimath/contract";

import { cagedCandidate, type CagedKind } from "./caged.js";
import { kakuroCandidate } from "./kakuro.js";
import { magicSquareCandidate } from "./magic-square.js";
import { wordSearchCandidate } from "./word-search.js";

/**
 * How many seeds one board may cost before the request is abandoned.
 *
 * Bounded, because a request that cannot be satisfied — a size whose candidates
 * are never unique, say — must stop rather than search forever.
 */
export const ATTEMPTS_PER_BOARD = 200;

export interface BatchRequest {
  readonly kind: CagedKind;
  readonly size: number;
  readonly count: number;
  readonly firstSeed: bigint;
}

export interface BatchReport {
  readonly attempts: number;
  readonly accepted: number;
  /** How many candidates each rejection tag accounted for. */
  readonly refused: Readonly<Record<string, number>>;
  /** True when the budget ran out before `count` boards were found. */
  readonly exhausted: boolean;
}

export interface Batch {
  readonly boards: readonly PuzzleEnvelope[];
  readonly report: BatchReport;
}

/**
 * A batch of caged boards, every one of them accepted by the frozen contract.
 *
 * **Propose and dispose** (design D1). A refused candidate is dropped and the
 * next seed tried; it is never adjusted until it passes, because knowing what
 * would fix it means owning a second solver.
 *
 * **The report is part of the return value** (design D5), not a log line. A
 * generator that quietly produces four boards when asked for ten looks exactly
 * like one that was asked for four, and the difference matters the moment
 * someone widens the size range and the hit rate collapses.
 *
 * `repeated_digit_in_cage` is a Killer-only decline: a cage the Latin square
 * gave a repeated digit. The proposer names it rather than folding it into one
 * generic tag, so a collapse in hit rate can be told apart from a contract
 * rejection.
 */
export function generateCagedBatch(request: BatchRequest, copy: PuzzleCopy): Batch {
  return collectBatch(request.count, request.firstSeed, copy, (seed) => {
    const candidate = cagedCandidate(request.kind, seed, request.size);
    return candidate === null
      ? "repeated_digit_in_cage"
      : { kind: candidate.kind, payload: candidate.payload };
  });
}

/**
 * A batch of sopas de letras, every one accepted by the frozen contract.
 *
 * The vocabulary is the caller's — which words a player meets is content.
 */
export function generateWordSearchBatch(
  request: WordSearchRequest,
  copy: PuzzleCopy,
): Batch {
  return collectBatch(request.count, request.firstSeed, copy, (seed) => {
    const candidate = wordSearchCandidate(seed, request.size, request.vocabulary);
    return candidate === null
      ? "no_word_fits_the_grid"
      : { kind: candidate.kind, payload: candidate.payload as Record<string, unknown> };
  });
}

/**
 * A batch of magic squares, every one accepted by the frozen contract.
 *
 * Takes no vocabulary and no kind: the format has one shape and one size knob.
 */
export function generateMagicSquareBatch(
  request: SizedRequest,
  copy: PuzzleCopy,
): Batch {
  return collectBatch(request.count, request.firstSeed, copy, (seed) =>
    magicSquareCandidate(seed, request.size));
}

/**
 * A batch of Kakuro boards, every one accepted by the frozen contract.
 */
export function generateKakuroBatch(
  request: SizedRequest,
  copy: PuzzleCopy,
): Batch {
  return collectBatch(request.count, request.firstSeed, copy, (seed) =>
    kakuroCandidate(seed, request.size));
}

export interface SizedRequest {
  readonly size: number;
  readonly count: number;
  readonly firstSeed: bigint;
}

export interface WordSearchRequest {
  readonly size: number;
  readonly count: number;
  readonly firstSeed: bigint;
  readonly vocabulary: readonly string[];
}

/**
 * What a proposer hands back: an envelope's kind and payload, or the name of
 * the reason it could not build one.
 *
 * A **name** and not a bare null, because "the proposer declined" and "the
 * contract refused" are different facts and the report has to tell them apart —
 * a Killer whose squares keep repeating a digit in a cage looks nothing like a
 * board the solver found two answers to.
 */
type Proposal =
  | { readonly kind: string; readonly payload: Record<string, unknown> }
  | string;

/**
 * Seeds in, accepted boards out — the loop every format shares.
 *
 * **Propose and dispose** (design D1). A refused candidate is dropped and the
 * next seed tried; it is never adjusted until it passes, because knowing what
 * would fix it means owning a second solver.
 *
 * **The report is part of the return value** (design D5), not a log line. A
 * generator that quietly produces four boards when asked for ten looks exactly
 * like one that was asked for four, and the difference matters the moment
 * someone widens the size range and the hit rate collapses.
 *
 * Shared rather than copied per format: the loop is one behaviour, and two
 * copies would be two chances to disagree about what "accepted" means.
 */
function collectBatch(
  count: number,
  firstSeed: bigint,
  copy: PuzzleCopy,
  propose: (seed: bigint) => Proposal,
): Batch {
  const boards: PuzzleEnvelope[] = [];
  const refused: Record<string, number> = {};
  const budget = count * ATTEMPTS_PER_BOARD;
  let attempts = 0;
  let seed = firstSeed;

  while (boards.length < count && attempts < budget) {
    attempts += 1;
    const seedUsed = seed;
    seed += 1n;

    const candidate = propose(seedUsed);
    if (typeof candidate === "string") {
      refused[candidate] = (refused[candidate] ?? 0) + 1;
      continue;
    }

    const envelope = {
      kind: candidate.kind,
      payload: candidate.payload,
      tutorial_steps: [...copy.tutorialSteps],
      reference_sheet: [...copy.referenceSheet],
    } as PuzzleEnvelope;

    const tag: PuzzleRejectionTag | null = parsePuzzle(envelope);
    if (tag !== null) {
      refused[tag] = (refused[tag] ?? 0) + 1;
      continue;
    }
    boards.push(envelope);
  }

  return {
    boards,
    report: {
      attempts,
      accepted: boards.length,
      refused,
      exhausted: boards.length < count,
    },
  };
}

/** The es-MX text every puzzle carries, supplied by the caller. */
export interface PuzzleCopy {
  readonly tutorialSteps: readonly string[];
  readonly referenceSheet: readonly string[];
}
