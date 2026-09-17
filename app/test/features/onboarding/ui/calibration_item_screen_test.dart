import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/design/theme.dart';
import 'package:akimath_app/design/tokens/tokens.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:akimath_app/features/onboarding/policy/calibration.dart';
import 'package:akimath_app/features/onboarding/ui/calibration_item_screen.dart';
import 'package:akimath_app/features/round/ui/verdict/verdict_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three items whose answers are `1`, `2` and `3`, so a test can be right or
/// wrong on purpose.
List<Item> _probe(int count) => <Item>[
      for (int index = 1; index <= count; index++)
        Item(
          id: 'probe-$index',
          stimulus: ArithmeticStimulus(<PromptToken>[
            PromptToken.text('$index'),
            PromptToken.operator('+'),
            PromptToken.text('0'),
            PromptToken.operator('='),
          ]),
          answer: PlainAnswer('$index'),
          ladderStep: 1,
        ),
    ];

/// The instants the screen's clock hands out, one per call.
///
/// **It hands the last one back for ever.** The screen reads the clock once
/// when the probe opens and once per submit, so a test that cares only about
/// the span of the whole probe can hand over two instants and let the rest
/// repeat; a test that cares about *per item* durations has to supply one
/// instant per submit and space them so no two items took the same time.
DateTime Function() _clockOf(List<DateTime> instants) {
  int next = 0;
  return () => instants[next < instants.length ? next++ : instants.length - 1];
}

/// One verdict the screen reported, with the time that item took.
typedef _Graded = ({Verdict verdict, Duration elapsed});

Future<void> _pump(
  WidgetTester tester, {
  required List<Item> items,
  required void Function(CalibrationOutcome) onFinished,
  DateTime Function()? now,
  void Function(Verdict verdict, Duration elapsed)? onGraded,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AkiMathTheme.build(),
      home: CalibrationItemScreen(
        items: items,
        onFinished: onFinished,
        onGraded: onGraded,
        now: now ?? DateTime.now,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Presses one key of the in-app keypad, by its id.
///
/// **Never the system keyboard**, which the app does not use for an answer.
Future<void> _press(WidgetTester tester, String id) async {
  await tester.tap(
    find.byWidgetPredicate((Widget w) => w is KeypadKeyView && w.data.id == id),
  );
  await tester.pump();
}

/// How many different colours the strip is drawn in.
///
/// The caller answers one item right and one wrong first, so a strip that
/// leaked the verdict would return three fills rather than two — filled and
/// empty, and nothing else.
Set<Color?> _distinctBarFills(WidgetTester tester) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byType(ProbeStrip),
        matching: find.byType(Container),
      ),
    )
    .map((Container bar) => (bar.decoration! as BoxDecoration).color)
    .toSet();

/// Types [answer] on the in-app keypad and submits it.
Future<void> _answer(WidgetTester tester, String answer) async {
  for (final String digit in answer.split('')) {
    await _press(tester, digit);
  }
  await _press(tester, 'submit');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the header counts this item against the probe, from one',
      (WidgetTester tester) async {
    await _pump(tester, items: _probe(3), onFinished: (_) {});

    expect(find.text('TE ESTOY CONOCIENDO · 1 DE 3'), findsOneWidget);
  });

  testWidgets('the strip has one bar per planned item, none of them done yet',
      (WidgetTester tester) async {
    await _pump(tester, items: _probe(3), onFinished: (_) {});

    final ProbeStrip strip = tester.widget<ProbeStrip>(find.byType(ProbeStrip));
    expect(strip.heights, hasLength(3));
    expect(strip.done, 0);
  });

  testWidgets('answering fills a bar, advances, and shows no verdict',
      (WidgetTester tester) async {
    await _pump(tester, items: _probe(3), onFinished: (_) {});

    await _answer(tester, '1');

    expect(find.byType(VerdictScreen), findsNothing);
    expect(find.text('TE ESTOY CONOCIENDO · 2 DE 3'), findsOneWidget);
    expect(tester.widget<ProbeStrip>(find.byType(ProbeStrip)).done, 1);
  });

  testWidgets('a wrong answer advances exactly like a right one',
      (WidgetTester tester) async {
    await _pump(tester, items: _probe(3), onFinished: (_) {});

    await _answer(tester, '9');

    expect(find.text('TE ESTOY CONOCIENDO · 2 DE 3'), findsOneWidget);
    expect(find.byType(VerdictScreen), findsNothing);
  });

  testWidgets('the last answer ends the probe with what was actually right',
      (WidgetTester tester) async {
    CalibrationOutcome? reported;
    await _pump(
      tester,
      items: _probe(3),
      onFinished: (CalibrationOutcome outcome) => reported = outcome,
      now: _clockOf(<DateTime>[
        DateTime.utc(2026, 8, 20, 9, 40),
        DateTime.utc(2026, 8, 20, 9, 40, 44),
      ]),
    );

    await _answer(tester, '1');
    await _answer(tester, '9');
    await _answer(tester, '3');

    expect(reported?.asked, 3);
    expect(reported?.answered, 3);
    expect(reported?.correct, 2);
    expect(reported?.elapsed, const Duration(seconds: 44));
  });

  testWidgets('leaving early reports what was answered and no more',
      (WidgetTester tester) async {
    CalibrationOutcome? reported;
    await _pump(
      tester,
      items: _probe(3),
      onFinished: (CalibrationOutcome outcome) => reported = outcome,
    );

    await _answer(tester, '1');
    await tester.tap(find.text('Saltar'));
    await tester.pumpAndSettle();

    expect(reported?.asked, 3);
    expect(reported?.answered, 1);
    expect(reported?.correct, 1);
    expect(reported?.hasSomethingToReport, isTrue);
  });

  testWidgets('leaving before answering anything reports nothing to report',
      (WidgetTester tester) async {
    CalibrationOutcome? reported;
    await _pump(
      tester,
      items: _probe(3),
      onFinished: (CalibrationOutcome outcome) => reported = outcome,
    );

    await tester.tap(find.text('Saltar'));
    await tester.pumpAndSettle();

    expect(reported?.answered, 0);
    expect(reported?.hasSomethingToReport, isFalse);
  });

  testWidgets('a system back leaves the probe, and does not quit the app',
      (WidgetTester tester) async {
    CalibrationOutcome? reported;
    await _pump(
      tester,
      items: _probe(3),
      onFinished: (CalibrationOutcome outcome) => reported = outcome,
    );
    await _answer(tester, '1');

    final NavigatorState navigator = tester.state(find.byType(Navigator));
    final bool handled = await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(handled, isTrue, reason: 'the back request went unhandled');
    expect(reported?.answered, 1);
  });

  testWidgets('every answered item is reported graded, timed from that item '
      'and not from the probe', (WidgetTester tester) async {
    final List<_Graded> graded = <_Graded>[];
    await _pump(
      tester,
      items: _probe(3),
      onFinished: (_) {},
      onGraded: (Verdict verdict, Duration elapsed) =>
          graded.add((verdict: verdict, elapsed: elapsed)),
      now: _clockOf(<DateTime>[
        DateTime.utc(2026, 8, 20, 9, 40),
        DateTime.utc(2026, 8, 20, 9, 40, 2),
        DateTime.utc(2026, 8, 20, 9, 40, 5),
        DateTime.utc(2026, 8, 20, 9, 40, 9),
      ]),
    );

    await _answer(tester, '1');
    await _answer(tester, '9');
    await _answer(tester, '3');

    expect(graded, <_Graded>[
      (verdict: Verdict.correct, elapsed: const Duration(seconds: 2)),
      (verdict: Verdict.wrong, elapsed: const Duration(seconds: 3)),
      (verdict: Verdict.correct, elapsed: const Duration(seconds: 4)),
    ]);
  });

  testWidgets('leaving reports the items answered and none of the rest',
      (WidgetTester tester) async {
    final List<_Graded> graded = <_Graded>[];
    await _pump(
      tester,
      items: _probe(3),
      onFinished: (_) {},
      onGraded: (Verdict verdict, Duration elapsed) =>
          graded.add((verdict: verdict, elapsed: elapsed)),
    );

    await _answer(tester, '9');
    await tester.tap(find.text('Saltar'));
    await tester.pumpAndSettle();

    expect(graded.map((_Graded g) => g.verdict), <Verdict>[Verdict.wrong]);
  });

  testWidgets('the strip is one colour, so it cannot leak how you are doing',
      (WidgetTester tester) async {
    await _pump(tester, items: _probe(3), onFinished: (_) {});

    await _answer(tester, '1');
    await _answer(tester, '9');

    expect(tester.widget<ProbeStrip>(find.byType(ProbeStrip)).done, 2);

    final Set<Color?> fills = _distinctBarFills(tester);

    expect(fills, hasLength(2), reason: 'filled and empty, and nothing else');
    expect(fills, isNot(contains(BrandColorRole.success.color)));
    expect(fills, isNot(contains(BrandColorRole.error.color)));
  });
}
