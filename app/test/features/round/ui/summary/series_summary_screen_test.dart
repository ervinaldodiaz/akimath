import 'package:akimath_app/content/model/diagnosis.dart';
import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/math/spec/es_mx_number.dart';
import 'package:akimath_app/design/widgets/baseline_meter.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:akimath_app/design/widgets/stat_tile.dart';
import 'package:akimath_app/design/widgets/verdict_ring.dart';
import 'package:akimath_app/features/round/ui/summary/series_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Diagnosis _stumble = Diagnosis(
  steps: <String>['Fíjate en cuánto crece la serie entre un número y el otro.'],
  explain: 'La diferencia crece; no es la misma cada vez.',
);

Future<void> _pump(
  WidgetTester tester, {
  int correct = 4,
  int total = 5,
  Duration elapsed = const Duration(seconds: 47),
  int streakDays = 3,
  List<Verdict> outcomes = const <Verdict>[
    Verdict.correct,
    Verdict.correct,
    Verdict.correct,
    Verdict.wrong,
    Verdict.correct,
  ],
  Diagnosis? stumble,
  int? stumbleIndex,
  VoidCallback? onDone,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: SeriesSummaryScreen(
        result: SeriesResult(
          correct: correct,
          total: total,
          elapsed: elapsed,
          streakDays: streakDays,
          outcomes: outcomes,
          stumble: stumble,
          stumbleIndex: stumbleIndex,
        ),
        onDone: onDone ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Iterable<String> _copy(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .where((String s) => s.isNotEmpty);

/// The figure inside a stat tile, found by its label.
String _tile(WidgetTester tester, String label) {
  final Finder tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(StatTile),
  );
  return tester
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .map((Text t) => t.data ?? '')
      .where((String text) => text != label)
      .join();
}

void main() {
  group('the ring is the series, item by item', () {
    testWidgets('one mark per answered item, in the order they were answered',
        (WidgetTester tester) async {
      await _pump(tester);

      final List<Verdict> drawn = tester
          .widgetList<VerdictRing>(find.byType(VerdictRing))
          .map((VerdictRing ring) => ring.verdict)
          .toList();

      expect(drawn, <Verdict>[
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
        Verdict.wrong,
        Verdict.correct,
      ]);
    });

    testWidgets(
        'a different series draws a different ring — the control, since a ring '
        'built from correct and total rather than from the outcomes would draw '
        'the same marks whatever the order',
        (WidgetTester tester) async {
      await _pump(tester, correct: 1, total: 2, outcomes: <Verdict>[
        Verdict.wrong,
        Verdict.correct,
      ]);

      final List<Verdict> drawn = tester
          .widgetList<VerdictRing>(find.byType(VerdictRing))
          .map((VerdictRing ring) => ring.verdict)
          .toList();

      expect(drawn, <Verdict>[Verdict.wrong, Verdict.correct]);
    });

    testWidgets('a series left part-way draws only what was answered',
        (WidgetTester tester) async {
      await _pump(tester, correct: 2, total: 5, outcomes: <Verdict>[
        Verdict.correct,
        Verdict.correct,
      ]);

      expect(find.byType(VerdictRing), findsNWidgets(2));
    });

    testWidgets(
        'with no outcomes at all the score is still stated in words, because '
        'an empty row would read as a clean sheet — the ring is a richer way '
        'of saying the score, never the only way it is said',
        (WidgetTester tester) async {
      await _pump(tester, outcomes: const <Verdict>[]);

      expect(find.byType(VerdictRing), findsNothing);
      expect(find.text('4 de 5'), findsOneWidget);
    });
  });

  group('the two tiles', () {
    testWidgets(
        'the total time and the streak and nothing else — the design draws '
        'three and the third was the rating, and counting them is what stops '
        'a fourth arriving unnoticed',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.byType(StatTile), findsNWidgets(2));
      expect(find.text('EN TOTAL'), findsOneWidget);
      expect(_tile(tester, 'RACHA'), '3');
    });

    testWidgets('the time is the whole series and not the last item',
        (WidgetTester tester) async {
      await _pump(tester, elapsed: const Duration(milliseconds: 51400));

      expect(
        _tile(tester, 'EN TOTAL'),
        EsMxNumber.seconds(51.4, places: 1),
        reason: 'built with the same formatter, so the claim is about which '
            'duration reaches the tile and not how a decimal is spelled',
      );
    });
  });

  group('nothing on it is a figure the product cannot produce', () {
    testWidgets(
        'the three blocks the design draws from nothing are absent, asserted '
        'by widget type as well as by label so a meter cannot outlive its '
        'heading',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.textContaining('RATING'), findsNothing);
      expect(find.textContaining('QUÉ MEJORÓ'), findsNothing);
      expect(find.byType(BaselineMeter), findsNothing);
      expect(find.textContaining('QUÉ SIGUE'), findsNothing);
    });

    testWidgets(
        'and the two tiles left are the measured ones — the other half, since '
        'a screen drawing no tiles at all would satisfy the assertion above '
        'and be a different defect',
        (WidgetTester tester) async {
      await _pump(tester, elapsed: const Duration(seconds: 47), streakDays: 3);

      expect(_tile(tester, 'EN TOTAL'), EsMxNumber.seconds(47, places: 1));
      expect(_tile(tester, 'RACHA'), '3');
    });

    testWidgets(
        'a clean series ends on the streak with nothing under it — the '
        'shortest the screen gets, pinning that removing the invented blocks '
        'left no heading over nothing behind (DR-P2)',
        (WidgetTester tester) async {
      await _pump(tester, correct: 5, outcomes: const <Verdict>[
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
      ]);

      expect(find.text('QUÉ SE TORCIÓ'), findsNothing);
      expect(find.byType(StatTile), findsNWidgets(2));
      expect(find.text('Volver al inicio'), findsOneWidget);
    });
  });

  group('what went wrong is the pack\'s words or nothing at all', () {
    testWidgets('the block appears when the series carries a stumble',
        (WidgetTester tester) async {
      await _pump(tester, stumble: _stumble);

      expect(find.text('QUÉ SE TORCIÓ'), findsOneWidget);
      expect(find.text(_stumble.steps.single), findsOneWidget);
    });

    testWidgets(
        'it names the item counting from one, because a player reading advice '
        'about a mistake needs to know which of five it was about',
        (WidgetTester tester) async {
      await _pump(tester, stumble: _stumble, stumbleIndex: 3);

      expect(find.text('Reto 4'), findsOneWidget);
    });

    testWidgets(
        'and is absent when nothing went wrong, because a heading over nothing '
        'is what 4.1 refuses with HISTORIAL',
        (WidgetTester tester) async {
      await _pump(tester, correct: 5, outcomes: const <Verdict>[
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
        Verdict.correct,
      ]);

      expect(find.text('QUÉ SE TORCIÓ'), findsNothing);
    });

    testWidgets(
        'and absent when the pack declares no copy for the slip — the ring '
        'still shows the slip, and only the explanation is missing because '
        'there is none to give',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('QUÉ SE TORCIÓ'), findsNothing);
      expect(find.byType(VerdictRing), findsNWidgets(5));
    });
  });

  group('one way back to the home', () {
    testWidgets('the primary button calls onDone', (WidgetTester tester) async {
      int done = 0;
      await _pump(tester, onDone: () => done++);

      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      expect(done, 1);
    });

    testWidgets(
        'and nothing offers a destination that does not exist — 2.5 draws a '
        'second button, nothing reviews a past item, so it is absent rather '
        'than dead',
        (WidgetTester tester) async {
      await _pump(tester, stumble: _stumble);

      expect(find.text('Ver el reto que falló'), findsNothing);
    });
  });

  group('it never scolds, at any score', () {
    testWidgets(
        'none of the four forbidden words, from 0 to 5 — the same sweep '
        'verdict_screen_test.dart runs, because req-diagnosis-copy is about '
        'the product and not about one screen',
        (WidgetTester tester) async {
      for (int correct = 0; correct <= 5; correct++) {
        await _pump(tester, correct: correct, stumble: _stumble);
        final String all = _copy(tester).join(' ').toLowerCase();
        for (final String forbidden in <String>[
          'incorrecto',
          'error',
          'fallaste',
          'mal',
        ]) {
          expect(all, isNot(contains(forbidden)), reason: '$correct de 5');
        }
      }
    });

    testWidgets('and still says something at zero', (WidgetTester tester) async {
      await _pump(tester, correct: 0);

      expect(_copy(tester), isNotEmpty);
      expect(find.byType(Aki), findsOneWidget);
    });

    testWidgets(
        'the copy changes with the score — the control, since one fixed '
        'sentence would pass every assertion above',
        (WidgetTester tester) async {
      await _pump(tester, correct: 5);
      final String perfect = _copy(tester).join(' ');
      await _pump(tester, correct: 0);

      expect(perfect, isNot(_copy(tester).join(' ')));
    });
  });

  group('the house rules hold here too', () {
    testWidgets('no visible timer', (WidgetTester tester) async {
      await _pump(tester);
      for (final String text in _copy(tester)) {
        expect(text, isNot(matches(RegExp(r'\d+:\d\d'))));
      }
    });
  });
}
