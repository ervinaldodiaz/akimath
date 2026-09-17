import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:akimath_app/design/widgets/stat_tile.dart';
import 'package:akimath_app/design/widgets/verdict_ring.dart';
import 'package:akimath_app/features/round/ui/verdict/verdict_screen.dart';
import 'package:akimath_app/content/model/diagnosis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Verdict verdict) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: VerdictScreen(
        summary: VerdictSummary(
          verdict: verdict,
          elapsed: const Duration(milliseconds: 4200),
          streakDays: 7,
        ),
        onContinue: () {},
        onClose: () {},
      ),
    ),
  );
}

Iterable<String> _copy(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text t) => t.data ?? '')
    .where((String s) => s.isNotEmpty);

void main() {
  group('a wrong answer is told why', () {
    testWidgets('the steps are drawn', (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: VerdictScreen(
            summary: const VerdictSummary(
              verdict: Verdict.wrong,
              elapsed: Duration(seconds: 9),
              streakDays: 3,
              diagnosis: Diagnosis(
                steps: <String>[
                  'Fíjate en cuál número va primero.',
                  'Quita el segundo al primero, en ese orden.',
                ],
                explain: 'Al restar, el orden importa.',
              ),
            ),
            onContinue: () {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('cuál número va primero'), findsOneWidget);
      expect(find.textContaining('en ese orden'), findsOneWidget);
    });

    testWidgets(
        'the paragraph is not printed as well, because `explain` says the same '
        'thing at length and a screen printing both asks a player to read it '
        'twice',
        (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: VerdictScreen(
            summary: const VerdictSummary(
              verdict: Verdict.wrong,
              elapsed: Duration(seconds: 9),
              streakDays: 3,
              diagnosis: Diagnosis(
                steps: <String>['Fíjate en cuál número va primero.'],
                explain: 'Al restar, el orden importa mucho de verdad.',
              ),
            ),
            onContinue: () {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('importa mucho de verdad'), findsNothing);
    });

    testWidgets(
        'a correct answer is told nothing even if handed a diagnosis — nothing '
        'constructs the pairing, and the screen still must not print an '
        'explanation over a right answer',
        (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: VerdictScreen(
            summary: const VerdictSummary(
              verdict: Verdict.correct,
              elapsed: Duration(seconds: 4),
              streakDays: 3,
              diagnosis: Diagnosis(
                steps: <String>['Fíjate en cuál número va primero.'],
                explain: 'x',
              ),
            ),
            onContinue: () {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('cuál número va primero'), findsNothing);
    });
  });


  group('the error screen names the reasoning, never the failure', () {
    testWidgets(
        'none of the four forbidden words appears, asserted over the rendered '
        'tree rather than trusted to review and over both moods rather than '
        'only the wrong one — a scolding word is no better on a right answer',
        (WidgetTester tester) async {
      for (final Verdict verdict in Verdict.values) {
        await _pump(tester, verdict);

        final String all = _copy(tester).join(' ').toLowerCase();
        for (final String forbidden in <String>[
          'incorrecto',
          'error',
          'fallaste',
          'mal',
        ]) {
          expect(
            all,
            isNot(contains(forbidden)),
            reason: '"$forbidden" reached the ${verdict.name} screen',
          );
        }
      }
    });

    testWidgets(
        'the wrong screen still says something, since passing the check above '
        'by rendering no copy at all would be worse than scolding',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.wrong);
      expect(_copy(tester), isNotEmpty);
      expect(find.textContaining('Casi'), findsOneWidget);
    });
  });

  group('Aki is present here and stoops rather than scolds', () {
    testWidgets('a right answer shows the correct pose',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.correct);
      expect(tester.widget<Aki>(find.byType(Aki)).pose, AkiPose.correct);
    });

    testWidgets(
        'a wrong answer shows the slip pose and never a sad one — the tail '
        'curl is the one body part that can be lost and come back, and it is '
        'already growing back in green, which is the whole cost',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.wrong);
      expect(tester.widget<Aki>(find.byType(Aki)).pose, AkiPose.slip);
    });

    testWidgets(
        'her art overflows the band upward rather than clipping — 182 px of '
        'art in a 156 px band, where a fixed-height Column child would clip '
        'or throw',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.wrong);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Aki)).width, 182);
    });
  });

  group('two tiles, and no number sync can contradict', () {
    testWidgets('time and streak, and nothing else', (WidgetTester tester) async {
      await _pump(tester, Verdict.correct);

      expect(find.byType(StatTile), findsNWidgets(2));
      expect(find.text('TIEMPO'), findsOneWidget);
      expect(find.text('RACHA'), findsOneWidget);
    });

    testWidgets('the recorded time renders as 4,2 s',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.correct);
      expect(find.text('4,2 s'), findsOneWidget);
    });

    testWidgets(
        'no rating appears and no placeholder for one, so nothing here is a '
        'figure sync could later contradict — a greyed-out pill would be '
        'exactly that (Q3)',
        (WidgetTester tester) async {
      for (final Verdict verdict in Verdict.values) {
        await _pump(tester, verdict);
        final String all = _copy(tester).join(' ').toLowerCase();
        expect(all, isNot(contains('rating')));
        expect(all, isNot(contains('puntos')));
      }
    });

    testWidgets('the raised variant is used for a win and flat for a slip',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.correct);
      expect(
        tester.widgetList<StatTile>(find.byType(StatTile)).first.variant,
        StatTileVariant.raised,
      );

      await _pump(tester, Verdict.wrong);
      expect(
        tester.widgetList<StatTile>(find.byType(StatTile)).first.variant,
        StatTileVariant.flat,
      );
    });
  });

  group('the verdict itself is carried by shape, not hue', () {
    testWidgets('the ring renders the verdict it was given',
        (WidgetTester tester) async {
      for (final Verdict verdict in Verdict.values) {
        await _pump(tester, verdict);
        expect(
          tester.widget<VerdictRing>(find.byType(VerdictRing)).verdict,
          verdict,
        );
      }
    });
  });

  group('no timer is shown here either', () {
    testWidgets('the elapsed figure is a stat, not a running clock',
        (WidgetTester tester) async {
      await _pump(tester, Verdict.correct);

      for (final String text in _copy(tester)) {
        expect(text, isNot(matches(RegExp(r'\d+:\d\d'))),
            reason: '"$text" reads as a clock; `4,2 s` is a measurement');
      }
    });
  });
}
