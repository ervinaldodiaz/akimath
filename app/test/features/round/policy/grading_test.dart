import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/features/round/policy/grading.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every expected answer in the shipped fixture must be storage-canonical.
///
/// This caught a real one: `demo-4` was written `−7` with U+2212, which stored
/// mode refuses. It would have shown the player a wrong verdict for the right
/// answer, on a device, with no error anywhere.
const Item _threeQuarters = Item(
  id: 'demo-1',
  stimulus: ArithmeticStimulus(<PromptToken>[
    PromptToken.fraction(numerator: '3', denominator: '4'),
    PromptToken.operator('+'),
    PromptToken.fraction(numerator: '2', denominator: '4'),
  ]),
  answer: PlainAnswer('5/4'),
  ladderStep: 3,
);

void main() {
  group('grading compares canonical forms', () {
    test('the expected answer is correct', () {
      expect(grade(_threeQuarters, '5/4'), Verdict.correct);
    });

    test('a different answer is wrong', () {
      expect(grade(_threeQuarters, '4/5'), Verdict.wrong);
    });

    test('surrounding whitespace does not change the verdict', () {
      expect(grade(_threeQuarters, ' 5/4 '), Verdict.correct);
    });

    test('the learner form strips leading zeros, so 007 is 7', () {
      expect(grade(_threeQuarters, '05/4'), Verdict.correct);
    });

    test('a fraction is not reduced, because calling 10/8 and 5/4 the same '
        'answer is a pedagogical call the contract does not make', () {
      expect(grade(_threeQuarters, '10/8'), Verdict.wrong);
    });

    test('both spellings of a minus grade correct, because storage is ASCII '
        'and the keypad emits U+2212', () {
      const Item negative = Item(
        id: 'demo-2',
        stimulus: ArithmeticStimulus(<PromptToken>[PromptToken.text('2 − 9')]),
        answer: PlainAnswer('-7'),
        ladderStep: 1,
      );
      expect(grade(negative, '-7'), Verdict.correct);
      expect(grade(negative, '−7'), Verdict.correct);
    });
  });

  group('grading reads nothing but its arguments', () {
    test('the same call twice gives the same verdict', () {
      expect(grade(_threeQuarters, '5/4'), grade(_threeQuarters, '5/4'));
    });

    test('an empty answer is wrong rather than an error', () {
      expect(grade(_threeQuarters, ''), Verdict.wrong);
    });

    test('an answer a player can produce but nothing can parse is wrong '
        'rather than an error, because the round has no error state (DR-K4)',
        () {
      for (final String nonsense in <String>['1/0', 'x+1', '−']) {
        expect(grade(_threeQuarters, nonsense), Verdict.wrong);
      }
    });

    test('an expected answer that is not canonical never grades correct, so a '
        'broken fixture says so instead of passing by accident', () {
      const Item broken = Item(
        id: 'broken',
        stimulus: ArithmeticStimulus(<PromptToken>[PromptToken.text('1 + 1')]),
        answer: PlainAnswer(' 002 '),
        ladderStep: 1,
      );
      expect(grade(broken, '2'), Verdict.wrong);
    });
  });
}
