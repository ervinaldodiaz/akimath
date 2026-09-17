import { z } from "zod";

import type { StimulusRejectionTag } from "./rejection.js";

/**
 * The function machine: worked examples go in, the player infers the rule and
 * answers for `query_input`. Two examples is the floor because one fixes no
 * operation.
 */
export const HiddenOperationPayloadSchema = z.strictObject({
  examples: z
    .array(z.strictObject({ input: z.int(), output: z.int() }))
    .min(2)
    .max(3),
  query_input: z.int(),
});

export type HiddenOperationPayload = z.infer<typeof HiddenOperationPayloadSchema>;

export function checkHiddenOperation(
  payload: HiddenOperationPayload,
): StimulusRejectionTag | null {
  const alreadyShown: boolean = payload.examples.some(
    (example) => example.input === payload.query_input,
  );
  return alreadyShown ? "query_repeats_example" : null;
}
