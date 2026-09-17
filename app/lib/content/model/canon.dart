/// The Dart half of the frozen answer canonicaliser.
///
/// `packages/contract` froze what a canonical answer is, in TypeScript. This is
/// the same rule in Dart, and `canon_test.dart` checks it against
/// `contract/fixtures/canon.golden.json` — **the fixture, not a copy of it**.
/// R2 is the risk that two implementations of one rule drift apart, and a
/// shared oracle is the only thing that catches it.
///
/// Pure: a string in, a result out. No clock, no network, no storage.
library;

/// How strictly a value is read.
enum CanonMode {
  /// What a player typed. Normalises: folds spaces, the fraction slash and the
  /// minus sign, and strips leading zeros.
  learner,

  /// What a system stored. Must **already** be canonical; anything that would
  /// have to be normalised is rejected rather than quietly fixed, so a
  /// malformed record cannot masquerade as a valid one.
  stored,
}

/// The outcome of canonicalising a value.
class CanonResult {
  const CanonResult.ok(this.value)
      : tag = null,
        ok = true;

  const CanonResult.rejected(this.tag)
      : value = null,
        ok = false;

  final bool ok;

  /// The canonical form, when accepted.
  final String? value;

  /// Why it was refused. The tags are the contract's, shared with TypeScript.
  final String? tag;
}

/// Characters that occupy no width and would let two visually identical
/// answers compare unequal.
///
/// **The set and the order are the contract's, not this file's.** Differential
/// fuzzing against `packages/contract/src/canon.ts` over 22,440 inputs found
/// 4,916 tag-only divergences: Dart hard-coded six digit blocks, four combining
/// ranges and five invisible code points where TypeScript uses `\p{Nd}`,
/// `\p{M}` and a wider invisible set, and the two checked in different orders.
/// Both sides rejected the same inputs, so no verdict moved — but the tags are a
/// shared contract a caller may switch on, so the drift was real and only
/// latent.
final RegExp _invisible =
    RegExp(r'[\u00AD\u200B-\u200F\u2028\u2029\u2060\uFEFF]', unicode: true);

/// Any Unicode mark. `1` followed by U+0301 looks like `1`.
final RegExp _combiningMark = RegExp(r'\p{M}', unicode: true);

/// Any Unicode decimal digit.
final RegExp _decimalDigit = RegExp(r'\p{Nd}', unicode: true);

/// A decimal digit that is not an ASCII one — Arabic-Indic, Thai, Devanagari.
///
/// Rejected rather than folded: `٠` and `0` are the same number and different
/// text, and silently equating them is a decision the contract does not make.
bool _hasNonAsciiDigit(String raw) {
  for (final int rune in raw.runes) {
    final String character = String.fromCharCode(rune);
    if (_decimalDigit.hasMatch(character) &&
        !(rune >= 0x30 && rune <= 0x39)) {
      return true;
    }
  }
  return false;
}

/// The character map the fixture declares: space removed, U+2044 FRACTION
/// SLASH folded to `/`, U+2212 MINUS SIGN folded to `-`.
String _fold(String value) => value
    .replaceAll(' ', '')
    .replaceAll('⁄', '/')
    .replaceAll('−', '-');

/// `-?digits` optionally over `digits`.
final RegExp _shape = RegExp(r'^-?\d+(?:/\d+)?$');

/// Removes leading zeros, keeping a single zero.
String _stripLeadingZeros(String digits) {
  final String stripped = digits.replaceFirst(RegExp(r'^0+'), '');
  return stripped.isEmpty ? '0' : stripped;
}

/// Reduces [raw] to its canonical form, or says why it cannot.
///
/// Order matters and is the contract's: the character-class refusals come
/// before the shape check, so `٠` is reported as a non-ASCII digit rather than
/// as something non-numeric.
CanonResult canonicalise(String raw, {required CanonMode mode}) {
  final CanonResult learner = _asLearner(raw);

  if (mode == CanonMode.learner || !learner.ok) {
    return learner;
  }

  // Stored values must already be what the learner form produces. Anything
  // that had to be normalised was not canonical to begin with.
  return raw == learner.value
      ? learner
      : const CanonResult.rejected('not_canonical');
}

CanonResult _asLearner(String raw) {
  // The three character-class refusals run on the **raw** string, before
  // folding, and in this order. Both are the contract's: a value carrying an
  // invisible character and a non-ASCII digit reports `invisible_character`,
  // not `non_ascii_digit`.
  if (_invisible.hasMatch(raw)) {
    return const CanonResult.rejected('invisible_character');
  }
  if (_combiningMark.hasMatch(raw)) {
    return const CanonResult.rejected('combining_mark');
  }
  if (_hasNonAsciiDigit(raw)) {
    return const CanonResult.rejected('non_ascii_digit');
  }

  final String folded = _fold(raw);
  if (folded.isEmpty) {
    return const CanonResult.rejected('empty');
  }
  if (!_shape.hasMatch(folded)) {
    return const CanonResult.rejected('non_numeric');
  }

  final bool negative = folded.startsWith('-');
  final String body = negative ? folded.substring(1) : folded;
  final List<String> parts = body.split('/');

  final String numerator = _stripLeadingZeros(parts.first);

  if (parts.length == 1) {
    return CanonResult.ok(_signed(numerator, numerator, negative));
  }

  final String denominator = _stripLeadingZeros(parts[1]);
  if (denominator == '0') {
    return const CanonResult.rejected('zero_denominator');
  }

  // **A fraction is never reduced.** 2/4 and 1/2 are different answers, and
  // deciding they are the same is a pedagogical call this layer does not make.
  return CanonResult.ok(
    _signed('$numerator/$denominator', numerator, negative),
  );
}

/// Applies the sign, suppressing it when the magnitude is zero.
///
/// **Both shapes, which is the fix for a real divergence.** The integer branch
/// suppressed the sign on `-0` and the fraction branch re-applied it
/// unconditionally, so Dart canonicalised `-0/5` to `-0/5` where the frozen
/// TypeScript produced `0/5` — and worse, Dart *accepted* `-0/5` as already
/// canonical in stored mode where the contract rejects it.
///
/// The consequence was reachable through content, not just across the wire: a
/// pack authored with `"answer": "-0/5"` passed `Pack._item`'s guard, loaded
/// clean, and told a player typing `0/5` they were wrong, with nothing reporting
/// anything.
///
/// The golden fixture did not catch it — its 19 vectors contain no `-0/n` case.
/// It was found by differential fuzzing the two implementations against each
/// other, which is the check the fixture approximates and does not replace.
String _signed(String value, String magnitude, bool negative) =>
    negative && magnitude != '0' ? '-$value' : value;
