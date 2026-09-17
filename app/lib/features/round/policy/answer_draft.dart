/// What the player has typed so far.
///
/// Pure and immutable: every edit returns a new draft. It reads no clock, no
/// keypad and no widget — the keypad reports a key, the screen hands the
/// character here, and this decides what the answer text becomes.
///
/// **It does not decide whether an answer is correct.** That is `grade`'s job in
/// `grading.dart`, and the separation matters: `ARCHITECTURE.md` §4 keeps the answer off
/// the wire and `packages/contract` froze what a canonical answer is.
library;

class AnswerDraft {
  const AnswerDraft(this.text);

  static const AnswerDraft empty = AnswerDraft('');

  /// Long enough for anything the corpus asks for, short enough that a player
  /// holding a key cannot overflow the slot the overflow gate protects.
  static const int maxLength = 12;

  /// U+2212 MINUS SIGN. Never U+002D — the keypad emits this and the draft
  /// stores exactly what it was given.
  static const String minusSign = '−';

  /// U+002C, the es-MX decimal separator.
  static const String decimalSeparator = ',';

  /// The characters a canonical answer can contain.
  ///
  /// **This is narrower than what the keypad offers, and that is a real
  /// conflict rather than an oversight.** `KeypadLayout.item` ships a decimal
  /// key (`,`) and a square key (`²`) because the design draws them, and the
  /// frozen answer shape — `-?digits` optionally over `digits` — admits
  /// neither. Before this check, one tap on either key produced a draft that
  /// `grade` could only ever score **wrong**: two keys of sixteen that punished
  /// a player for the app's own gap, with `canSubmit` returning true for a draft
  /// of nothing but `,`.
  ///
  /// Refusing them here is the safe half of the fix. The other half is a
  /// decision nobody has taken: either the contract grows a decimal answer
  /// shape, or those keys come off the item pad. Recorded rather than settled —
  /// see this change's ledger.
  static const Set<String> acceptedCharacters = <String>{
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
    minusSign,
    '/',
  };

  final String text;

  /// Appends [character], if the result is still a well-formed answer.
  ///
  /// Refusals are silent by design: no document specifies feedback for an
  /// illegal keypress, and inventing a shake or a tone here would be inventing
  /// a design (DR-K4). Silent is also strictly better than the alternative that
  /// was there — accepting a character the grader cannot read, and scoring the
  /// result wrong.
  AnswerDraft type(String character) {
    if (!acceptedCharacters.contains(character)) {
      return this;
    }
    if (text.length >= maxLength) {
      return this;
    }
    if (_minusArrivingWhereItIsNotASign(character)) {
      return this;
    }
    return AnswerDraft('$text$character');
  }

  /// Whether [character] is a minus sign arriving somewhere it cannot mean
  /// anything.
  ///
  /// A minus is a sign and not an operator: it reads only in front of the
  /// digits, so one typed after anything at all is a keypress with no meaning
  /// rather than a subtraction.
  bool _minusArrivingWhereItIsNotASign(String character) =>
      character == minusSign && text.isNotEmpty;

  AnswerDraft backspace() =>
      text.isEmpty ? this : AnswerDraft(text.substring(0, text.length - 1));

  /// Whether there is an answer here to submit.
  ///
  /// A lone minus sign is not one — it is a sign with nothing after it.
  bool get canSubmit => text.isNotEmpty && text != minusSign;
}
