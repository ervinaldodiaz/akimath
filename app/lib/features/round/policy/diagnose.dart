import '../../../content/model/diagnosis.dart';
import '../../../design/widgets/spec/verdict.dart';

/// What to tell a player about the answer they gave.
///
/// **PURE.** Item, answer and the pack's fallback in; copy or null out. No
/// clock, no store, no screen.
///
/// **A correct answer gets nothing**, and the verdict is **handed in** rather
/// than re-decided. It used to call `grade` itself, on the sound ground that
/// two implementations of "is this right" is the drift that would let the
/// verdict screen say *Acierto* while explaining away a mistake underneath it.
/// Taking it as an argument is the same argument carried further: there is now
/// one decision, made once by the caller, and no second call that could
/// disagree.
///
/// It is also what lets this work for an issued pack. `grade` reads a plaintext
/// answer, and a digest item has none — the call threw a `StateError` the first
/// time one was played, which is exactly the loudness `Item.expected` was given
/// for.
///
/// **Every wrong answer gets something.** A distractor the item anticipated
/// wins; anything else falls back. That matters more than it sounds, because
/// most wrong answers are unanticipated — the shipped pack anticipates four
/// items of seventy — and an empty diagnosis would leave the screen as bare as
/// it was before any of this existed.
///
/// **It no longer knows what an item is.** The key to look up is handed in,
/// because resolving one differs by how the answer is known: a plaintext item
/// keys its distractors by the canonical answer, and an issued one keys them by
/// the *digest* of it — a pack that listed its distractors in the clear would
/// name the right answer by omission. Computing a digest needs `package:crypto`
/// and this is a pure root, so `diagnoseItem` resolves the key and this picks
/// the copy.
///
/// **Only the typed side is canonicalised, and that is a decision** (design
/// D3). Learner mode folds the keypad's U+2212 to the hyphen a content author
/// types, which is the difference that would otherwise make every distractor
/// dead. The authored key is *not* canonicalised because it cannot need it:
/// `Pack.fromJson` refuses a key that is not already storage-canonical, by name
/// and at load.
///
/// **A null [key] needs no guard of its own.** It is what the caller hands over
/// when it could not resolve one — an answer the canonicaliser refused, which
/// no authored key can equal — so the lookup misses and the fallback answers,
/// which is the same thing an unanticipated wrong answer gets.
Diagnosis? diagnose({
  required Map<String, Diagnosis> distractors,
  required String? key,
  required Verdict verdict,
  required Diagnosis fallback,
}) {
  if (verdict == Verdict.correct) {
    return null;
  }

  return distractors[key] ?? fallback;
}
