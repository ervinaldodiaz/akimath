import { z } from "zod";

import { checkUnknownIndex, type StimulusRejectionTag } from "./rejection.js";

/**
 * Seven elastic tiles at most — the count `02 Reto activo` and the seven-cell
 * replay on `Error con diagnóstico` draw. `unknown_index` is the tile that
 * renders as `?`; the player's answer is the term it hides.
 */
export const NumberSeriesPayloadSchema = z.strictObject({
  terms: z.array(z.int()).min(3).max(7),
  unknown_index: z.int().min(0),
});

export type NumberSeriesPayload = z.infer<typeof NumberSeriesPayloadSchema>;

export function checkNumberSeries(payload: NumberSeriesPayload): StimulusRejectionTag | null {
  return checkUnknownIndex(payload.unknown_index, payload.terms.length);
}
