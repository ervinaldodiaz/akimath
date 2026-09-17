/// The probe's pure policy, and the one gate that reads the shipped pack.
///
/// **The `7 + 6` defect, guarded at the probe's end.** The probe takes the
/// pack's first ten, which is exactly where a teaching item edited back into
/// the pack would resurface. `ui/teaching_item_test.dart` holds the incident
/// itself and guards the home's end of the same rule.
///
/// Two of the cases here are PROC-11 controls rather than claims of their own.
/// *"the reader it uses can see a repeat"* is what stops the collision
/// assertion passing for a `_prompt` that returns the empty string for
/// everything, and *"they are not all the same"* is what `0.5` annotates the
/// strip with in as many words — *"las alturas cambian: no es una serie, es una
/// sonda"* — because a flat bar would read as a five-item series.
library;

import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/content/model/pack.dart';
import 'package:akimath_app/content/pack_reader.dart';
import 'package:akimath_app/features/onboarding/ui/first_item_screen.dart';
import 'package:akimath_app/features/onboarding/policy/calibration.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pack of [count] distinct arithmetic items, in a known order.
List<Item> _pack(int count) => <Item>[
      for (int index = 0; index < count; index++)
        Item(
          id: 'pack-$index',
          stimulus: ArithmeticStimulus(<PromptToken>[
            PromptToken.text('$index'),
            PromptToken.operator('+'),
            PromptToken.text('1'),
            PromptToken.operator('='),
          ]),
          answer: PlainAnswer('${index + 1}'),
          ladderStep: 1,
        ),
    ];

/// What an arithmetic prompt reads as, which is what a player recognises.
///
/// **The answer is not identity here.** `7 + 6` and `5 + 8` are both `13` and
/// are two different challenges; comparing the answers would call them the same
/// item and the test would be about arithmetic rather than about repetition.
String _prompt(Stimulus stimulus) => switch (stimulus) {
      ArithmeticStimulus(:final List<PromptToken> prompt) => prompt
          .map((PromptToken token) => switch (token) {
                TextToken(:final String value) => value,
                OperatorToken(:final String glyph) => glyph,
                FractionToken(
                  :final String numerator,
                  :final String denominator,
                ) =>
                  '$numerator/$denominator',
              })
          .join(' '),
      _ => '',
    };

void main() {
  group('the probe never asks the item the tutorial already asked', () {
    test('the shipped pack does not hold the teaching item', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final Pack pack = await const PackReader().load();
      final List<Item> plan = calibrationPlan(pack.items);

      expect(plan, isNotEmpty, reason: 'the shipped pack yielded no probe');
      expect(
        plan.map((Item item) => _prompt(item.stimulus)),
        isNot(contains(_prompt(FirstItemScreen.teachingItem.stimulus))),
      );
    });

    test('and the reader it uses can see a repeat when there is one', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final Pack pack = await const PackReader().load();
      final List<Item> plan = calibrationPlan(pack.items);

      expect(_prompt(FirstItemScreen.teachingItem.stimulus), '5 + 8 =');
      expect(
        plan.map((Item item) => _prompt(item.stimulus)),
        contains('7 + 6 ='),
        reason: 'the pack no longer opens with the item this rule is about',
      );
    });
  });

  group('the probe asks ten at most', () {
    test('a long pack yields exactly ten, in pack order', () {
      final List<Item> plan = calibrationPlan(_pack(70));

      expect(plan, hasLength(calibrationLength));
      expect(
        plan.map((Item item) => item.id),
        <String>[for (int index = 0; index < 10; index++) 'pack-$index'],
      );
    });

    test('a pack shorter than ten yields what it holds', () {
      expect(calibrationPlan(_pack(4)), hasLength(4));
    });

    test('an empty pack yields nothing, and does not throw', () {
      expect(calibrationPlan(const <Item>[]), isEmpty);
    });

    test('no item is asked twice', () {
      final List<Item> plan = calibrationPlan(_pack(70));

      expect(plan.map((Item item) => item.id).toSet(), hasLength(plan.length));
    });
  });

  group('the bar says where you are, never how you are doing', () {
    test('one bar per planned item', () {
      expect(probeBarHeights(10), hasLength(10));
      expect(probeBarHeights(4), hasLength(4));
      expect(probeBarHeights(0), isEmpty);
    });

    test('the heights are the ones the design draws', () {
      expect(
        probeBarHeights(10),
        <double>[22, 16, 22, 14, 20, 14, 22, 16, 20, 14],
      );
    });

    test('and they are not all the same, which is the whole point', () {
      expect(probeBarHeights(10).toSet().length, greaterThan(1));
    });

    test('a bar longer than the pattern keeps varying', () {
      expect(probeBarHeights(12), hasLength(12));
      expect(probeBarHeights(12).last, probeBarHeights(2).last);
    });
  });

  group('what the probe can honestly report', () {
    test('nothing answered is nothing to report', () {
      const CalibrationOutcome skipped = CalibrationOutcome(
        asked: 10,
        answered: 0,
        correct: 0,
        elapsed: Duration.zero,
      );

      expect(skipped.hasSomethingToReport, isFalse);
    });

    test('one answer is enough to report', () {
      const CalibrationOutcome partial = CalibrationOutcome(
        asked: 10,
        answered: 1,
        correct: 0,
        elapsed: Duration(seconds: 9),
      );

      expect(partial.hasSomethingToReport, isTrue);
      expect(partial.correct, 0);
    });

    test('an outcome carries what was answered, what was right and how long',
        () {
      const CalibrationOutcome outcome = CalibrationOutcome(
        asked: 10,
        answered: 6,
        correct: 4,
        elapsed: Duration(minutes: 2, seconds: 14),
      );

      expect(outcome.answered, 6);
      expect(outcome.correct, 4);
      expect(outcome.elapsed, const Duration(minutes: 2, seconds: 14));
    });

    test('two outcomes with the same figures are equal, so a widget test can '
        'assert on one', () {
      const CalibrationOutcome one = CalibrationOutcome(
        asked: 10,
        answered: 6,
        correct: 4,
        elapsed: Duration(seconds: 30),
      );
      const CalibrationOutcome other = CalibrationOutcome(
        asked: 10,
        answered: 6,
        correct: 4,
        elapsed: Duration(seconds: 30),
      );

      expect(one, other);
    });
  });
}
