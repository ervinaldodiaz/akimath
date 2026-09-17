import 'package:akimath_app/content/model/diagnosis.dart';
import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/content/answer_digest.dart';
import 'package:flutter_test/flutter_test.dart';

const Diagnosis _reversed = Diagnosis(
  steps: <String>[
    'Fíjate en cuál número va primero.',
    'Quita el segundo al primero, en ese orden.',
  ],
  explain: 'Al restar, el orden importa.',
);

const Diagnosis _fallback = Diagnosis(
  steps: <String>['Lee otra vez el reto, sin prisa.'],
  explain: 'Repasa el reto con calma.',
);

/// `26 − 17 = 9`. Subtracting in the wrong order gives `−9`, which is the
/// distractor every test in this file is about.
Item _item({Map<String, Diagnosis> distractors = const <String, Diagnosis>{}}) => Item(
      id: 'sub-1',
      stimulus: const ArithmeticStimulus(<PromptToken>[
        PromptToken.text('26'),
        PromptToken.operator('−'),
        PromptToken.text('17'),
        PromptToken.operator('='),
      ]),
      answer: PlainAnswer('9', distractors: distractors),
      ladderStep: 3,
    );

/// What the screen would say about [answer].
///
/// **The verdict is handed in**, so this computes it once with the same
/// function the round does and passes it along. Nothing here can disagree with
/// the screen, because nothing here decides the verdict a second time.
Diagnosis? _for(String answer, {Map<String, Diagnosis>? distractors}) {
  final Item item =
      _item(distractors: distractors ?? <String, Diagnosis>{'-9': _reversed});
  return diagnoseItem(
    item: item,
    typed: answer,
    verdict: gradeItem(item, answer),
    fallback: _fallback,
  );
}

void main() {
  group('a wrong answer always gets something to read', () {
    test('an anticipated one gets its own steps, so the player who subtracted '
        'backwards and the player who mistyped see different screens', () {
      expect(_for('-9'), _reversed);
    });

    test('anything else gets the fallback, which is the common case and the '
        'difference between a screen and a bare one', () {
      expect(_for('42'), _fallback);
    });

    test('an item carrying no distractors still gets the fallback', () {
      expect(_for('42', distractors: const <String, Diagnosis>{}), _fallback);
    });

    test('an answer the canonicaliser refuses outright gets the fallback '
        'rather than nothing, because that player is still owed a screen', () {
      expect(_for('9,0'), _fallback);
      expect(_for('--'), _fallback);
    });
  });

  group('the keypad\'s minus and the author\'s are the same minus', () {
    test('a typed U+2212 matches a distractor authored with a hyphen, which is '
        'the whole reason both sides go through the canonicaliser', () {
      expect(_for('−9'), _reversed);
      expect(_for('-9'), _reversed);
    });

    test('a different number does not match', () {
      expect(_for('90'), _fallback);
      expect(_for('-90'), _fallback);
    });

    test('a key that is not storage-canonical is a dead key whose player still '
        'gets the fallback, not a screen with nothing on it', () {
      expect(
        _for('-9', distractors: <String, Diagnosis>{'- 9': _reversed}),
        _fallback,
      );
    });

    test('the lookup is by canonical value and not by the raw text, which for '
        'a negative would miss every time', () {
      expect(
        _for('−9', distractors: <String, Diagnosis>{'-9': _reversed}),
        _reversed,
      );
    });
  });

  group('there is nothing to explain about a right answer', () {
    test('the correct answer gets no diagnosis', () {
      expect(_for('9'), isNull);
    });

    test('a distractor that shadows the correct answer never wins, because the '
        'handed-in verdict settles it before any lookup happens', () {
      expect(
        _for('9', distractors: <String, Diagnosis>{'9': _reversed}),
        isNull,
      );
    });
  });
}
