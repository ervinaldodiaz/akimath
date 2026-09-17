/// `0.6 Calibración resultado`, held to reporting only what the probe measured.
///
/// **`AkiPose` and the design document use different words for one pose.** The
/// document's `base` / `fan` / `error` are aliases of the code's `base` /
/// `correct` / `slip` (design decision D9), which is why a test named after the
/// design's *fan* asserts `AkiPose.correct`. Nothing on `AkiPose` itself
/// records the mapping, so it is written down here.
library;

import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/math/spec/es_mx_number.dart';
import 'package:akimath_app/design/theme.dart';
import 'package:akimath_app/features/onboarding/policy/calibration.dart';
import 'package:akimath_app/features/onboarding/ui/calibration_result_screen.dart';
import 'package:akimath_app/features/shell/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const CalibrationOutcome _sixOfTen = CalibrationOutcome(
  asked: 10,
  answered: 6,
  correct: 4,
  elapsed: Duration(minutes: 2, seconds: 14),
);

Future<void> _pump(
  WidgetTester tester, {
  CalibrationOutcome outcome = _sixOfTen,
  VoidCallback? onEnter,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AkiMathTheme.build(),
      home: AppShell(
        child: CalibrationResultScreen(
          outcome: outcome,
          onEnter: onEnter ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String> _copyOn(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text text) => text.data ?? '')
    .where((String line) => line.isNotEmpty)
    .toList();

void main() {
  testWidgets('the figures it reports are the ones the device measured',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text(EsMxNumber.ratio(4, 6)), findsOneWidget);
    expect(find.text(EsMxNumber.elapsed(const Duration(minutes: 2, seconds: 14))),
        findsOneWidget);
  });

  testWidgets('a different probe reports different figures, so neither is a '
      'constant', (WidgetTester tester) async {
    await _pump(
      tester,
      outcome: const CalibrationOutcome(
        asked: 10,
        answered: 10,
        correct: 9,
        elapsed: Duration(minutes: 4, seconds: 5),
      ),
    );

    expect(find.text(EsMxNumber.ratio(9, 10)), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
  });

  testWidgets('the rating card the design draws is absent, not blank',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.textContaining('RATING'), findsNothing);
    expect(find.text('AQUÍ EMPIEZAS'), findsOneWidget);
  });

  testWidgets('and the measured figures are still drawn, so "absent" is not '
      '"an empty screen"', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('ACIERTOS'), findsOneWidget);
    expect(find.text('TIEMPO'), findsOneWidget);
    expect(find.text(EsMxNumber.ratio(4, 6)), findsOneWidget);
  });

  testWidgets('and it says, in the design\'s words, that it is not a mark',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(
      find.text(
        'No es calificación. Es de dónde salimos, y se mueve todos los días.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('it claims no level, no rank and no place on a ladder',
      (WidgetTester tester) async {
    await _pump(tester);

    final Iterable<String> copy =
        _copyOn(tester).map((String line) => line.toLowerCase());

    for (final String claim in <String>['nivel', 'rango', 'lugar', 'puesto']) {
      expect(
        copy.where((String line) => line.contains(claim)),
        isEmpty,
        reason: 'the result screen said "$claim"',
      );
    }
  });

  testWidgets('Aki is wagging, which is the design\'s fan',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(tester.widget<Aki>(find.byType(Aki)).pose, AkiPose.correct);
  });

  testWidgets('the one button leaves for wherever the caller says',
      (WidgetTester tester) async {
    int entered = 0;
    await _pump(tester, onEnter: () => entered++);

    await tester.tap(find.text('Entrar a mi mapa'));
    await tester.pumpAndSettle();

    expect(entered, 1);
  });
}
