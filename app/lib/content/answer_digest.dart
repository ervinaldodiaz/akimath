/// The offline membership verifier `ARCHITECTURE.md` §4 asks for.
///
/// **ADAPTER, and only because of the import.** Everything here is a pure
/// function of its arguments — no clock, no socket, no environment — but
/// `package:crypto` is not on `pure_boundary_test.dart`'s allowlist, so this
/// sits in `content/` rather than `content/model/`. The rule is worth more than
/// the exception it would take to move it.
///
/// **A pack the server issued states a digest, never the answer**, so the
/// server never learns an authored answer and a player's device can still tell
/// right from wrong with no network. The message construction is a cross-stack
/// contract, frozen in `packages/contract/src/digest.ts` and pinned by
/// `contract/fixtures/digest.golden.json`, which this is tested against:
///
/// * the key is the pack's salt, **as bytes**, decoded from its hex — keying on
///   the hex characters produces a plausible digest that matches nothing;
/// * the message is the UTF-8 bytes of the **canonical** answer and nothing
///   else: no length prefix, no separator, no trailing newline;
/// * the output is lowercase hex, untruncated.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../design/widgets/spec/verdict.dart';
import 'model/canon.dart';
import 'model/diagnosis.dart';
import 'model/item.dart';
import '../features/round/policy/diagnose.dart';
import '../features/round/policy/grading.dart';

/// `HMAC-SHA256(salt, canonicalAnswer)`, lowercase hex.
///
/// [canonicalAnswer] must already be canonical — [answerMatches] is the entry
/// point that canonicalises first. Throws [FormatException] on a salt that is
/// not an even-length run of hex digits, because a salt nobody can decode is a
/// pack nobody can grade and guessing at it would mark every answer wrong.
String answerDigest({required String saltHex, required String canonicalAnswer}) {
  final Hmac mac = Hmac(sha256, _bytesOfHex(saltHex));
  return mac.convert(utf8.encode(canonicalAnswer)).toString();
}

/// Whether what a player typed is the answer this digest stands for.
///
/// **Canonicalises first, which is the whole point.** `2/4` and `1/2` are one
/// value and one canonical spelling, so they share a digest and nobody is
/// marked wrong for a keystroke.
///
/// **An unreadable answer is wrong, not a crash.** A player can type anything,
/// and `canonicalise` refuses plenty of it; a verifier that threw would turn a
/// stray character into a lost round.
bool answerMatches({
  required String saltHex,
  required String typed,
  required String digest,
}) {
  final CanonResult canonical = canonicalise(typed, mode: CanonMode.learner);
  if (!canonical.ok) {
    return false;
  }
  final String computed =
      answerDigest(saltHex: saltHex, canonicalAnswer: canonical.value!);
  // Case-insensitive: hex case is spelling, not meaning, and a pack written by
  // another tool may upper-case it.
  return computed == digest.toLowerCase();
}

List<int> _bytesOfHex(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('a salt needs an even number of hex digits', hex);
  }
  final List<int> bytes = <int>[];
  for (int at = 0; at < hex.length; at += 2) {
    final int? byte = int.tryParse(hex.substring(at, at + 2), radix: 16);
    if (byte == null) {
      throw FormatException('"${hex.substring(at, at + 2)}" is not hex', hex);
    }
    bytes.add(byte);
  }
  return bytes;
}

/// The verdict for an item, whichever way its answer is known.
///
/// **The adapter, and the reason it is one.** `features/round/policy/grading.dart`
/// is a pure root and cannot import `package:crypto`, so a digest item cannot be
/// graded there. Rather than thread a hashing closure through a pure function —
/// which would put the seam in the wrong place and make every caller carry it —
/// the pure policy keeps the case it can decide and this adds the one it cannot.
///
/// Both cases are the same rule: canonicalise what the player typed, compare it
/// with what the item states. Only the comparison differs, because in one the
/// item states the answer and in the other it states an HMAC of it.
Verdict gradeItem(Item item, String typed) => switch (item.answer) {
      PlainAnswer() => grade(item, typed),
      DigestAnswer(:final String digest, :final String saltHex) =>
        answerMatches(saltHex: saltHex, typed: typed, digest: digest)
            ? Verdict.correct
            : Verdict.wrong,
    };

/// What to tell a player about the answer they gave.
///
/// **The adapter half of `diagnose`, for the same reason `gradeItem` is.** The
/// key a distractor is looked up by differs with how the answer is known: a
/// plaintext item keys by the canonical answer, an issued one by the *digest*
/// of it. Computing that digest needs `package:crypto`, which a pure root
/// cannot import — so this resolves the key and the pure policy picks the copy.
Diagnosis? diagnoseItem({
  required Item item,
  required String typed,
  required Verdict verdict,
  required Diagnosis fallback,
}) {
  // Null when the canonicaliser refuses the input outright, which no key can
  // equal — so an unreadable answer falls through to the fallback.
  final String? canonical = canonicalise(typed, mode: CanonMode.learner).value;

  final String? key = switch (item.answer) {
    PlainAnswer() => canonical,
    DigestAnswer(:final String saltHex) => canonical == null
        ? null
        : answerDigest(saltHex: saltHex, canonicalAnswer: canonical),
  };

  return diagnose(
    distractors: item.distractors,
    key: key,
    verdict: verdict,
    fallback: fallback,
  );
}
