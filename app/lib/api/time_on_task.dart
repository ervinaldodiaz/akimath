/// The bound the frozen contract puts on `elapsedMs`, and what the device
/// sends when a measurement lands outside it.
///
/// **PURE** — a `Duration` in, a `Duration` out. It sits in `api/` beside
/// `instant.dart` for the same reason that one does: both re-derive a rule the
/// wire owns, and `test/api/contract_parity_test.dart` runs each against
/// `contract/openapi.json` itself so the re-derivation cannot drift from the
/// document.
///
/// **It exists because an out-of-range figure destroys the batch it travels
/// in.** `round_screen.dart` measures an item as a wall-clock difference and
/// nothing pauses it when the app goes to the background, so a phone put in a
/// pocket, a call taken or an app switched away from produces an `elapsedMs`
/// past the maximum. The server refuses the whole body with a 400,
/// `journalAfter` reads a 400 as a batch there is no point resending, and up to
/// two hundred real answers are deleted — with nothing on screen and nothing in
/// a log. That is the same failure path `AttemptSubmission`'s two-source
/// invariant was hardened against, reachable this time by an ordinary player
/// doing an ordinary thing.
///
/// **Why a capped figure rather than none.** This project would rather send
/// nothing than send something misleading, and here there is no nothing to
/// send: `elapsedMs` is in the frozen `AttemptSubmission`'s `required` list,
/// carries no `nullable`, and the schema is `additionalProperties: false`, so
/// absence is a 400 exactly like an overrun. Of the values the schema does
/// admit, the ceiling is the least committal: it reads as *at least this long*,
/// which is true, and a pile-up at exactly the maximum is the recognisable
/// signature of a saturated measurement. Zero would assert *instantaneous*,
/// which is affirmatively false and would poison any later reading of how fast
/// an item was answered.
///
/// **What time on task should mean when the app was backgrounded for forty
/// minutes is an open product question, and this file does not answer it.**
/// Pausing the timer on lifecycle events, or attributing only foreground time,
/// is a decision nobody has made; the least committal behaviour is chosen here
/// so that the safety property — nothing the device sends is a value the
/// contract rejects — holds whichever way that question is settled. Whoever
/// settles it changes what is *measured*, in `round_screen.dart`, and this
/// bound stays where it is: it is the wire's, not the product's.
library;

/// The longest time on task the frozen contract admits.
///
/// `AttemptSubmission.elapsedMs` is `{"minimum": 0, "maximum": 3600000}` in
/// `contract/openapi.json`. Stated here as a `Duration` because that is what
/// the client holds, and held to the document's own number by
/// `test/api/contract_parity_test.dart`.
///
/// **`maximum` in JSON Schema is inclusive**, so the boundary belongs to the
/// in-range side: an off-by-one would send 3_599_999 for an hour, or — the
/// direction that matters — leave 3_600_001 alone.
const Duration maxReportableTimeOnTask = Duration(hours: 1);

/// The measurement, brought inside the bound the wire will accept.
///
/// Saturating, not wrapping and not refusing: a throw here would wedge every
/// later flush on one poisoned row, and the answer is the part worth keeping —
/// the timing is not what the player earned.
Duration reportableTimeOnTask(Duration measured) {
  if (measured.isNegative) {
    return Duration.zero;
  }
  return measured > maxReportableTimeOnTask ? maxReportableTimeOnTask : measured;
}
