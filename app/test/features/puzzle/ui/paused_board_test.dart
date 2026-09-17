/// `Pausa` on screen: the board covered, and only what it can keep promised.
///
/// **It shows nothing that reads as a clock** — the rule
/// `quiet_while_you_solve_test.dart` enforces over every solving surface,
/// asserted here too because this is the screen that was asked for *with* an
/// elapsed time on it.
///
/// **And the way out is not *Guardar y salir*.** The design's label promises a
/// board that comes back, and nothing here writes one to disk: a half-finished
/// board lives in memory for as long as the screen does, so a button claiming
/// to save is the one thing this screen must not draw (LANG-2).
library;

import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/theme.dart';
import 'package:akimath_app/features/puzzle/policy/pause.dart';
import 'package:akimath_app/features/puzzle/ui/paused_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const PauseSummary _summary = PauseSummary(
  filled: 11,
  total: 36,
  formatName: 'KENKEN',
  sizeLabel: '6 × 6',
);

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onResume,
  VoidCallback? onLeave,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AkiMathTheme.build(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: PausedBoardView(
          summary: _summary,
          onResume: onResume ?? () {},
          onLeave: onLeave ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a paused board', () {
    testWidgets('says it is paused', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('EN PAUSA'), findsOneWidget);
    });

    testWidgets('reports how much of the board is filled and which board it is',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('11'), findsOneWidget);
      expect(find.text('DE 36 CELDAS'), findsOneWidget);
      expect(find.text('KENKEN'), findsOneWidget);
      expect(find.text('6 × 6'), findsOneWidget);
    });

    testWidgets('shows nothing that reads as a clock', (WidgetTester tester) async {
      await _pump(tester);

      final RegExp clock =
          RegExp(r'\b\d+:[0-5]\d\b|\b\d+([.,]\d+)?\s*(s|seg|segundos|min)\b');
      final List<String> ticking = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where(clock.hasMatch)
          .toList();

      expect(ticking, isEmpty);
    });

    testWidgets('is not watched by Aki either', (WidgetTester tester) async {
      await _pump(tester);

      expect(
        find.byWidgetPredicate((Widget w) => w is Aki || w is AkiFace),
        findsNothing,
      );
    });

    testWidgets('goes back to the board', (WidgetTester tester) async {
      int resumed = 0;
      await _pump(tester, onResume: () => resumed++);

      await tester.tap(find.text('Reanudar'));
      await tester.pumpAndSettle();

      expect(resumed, 1);
    });

    testWidgets('and leaves it, saying what leaving costs',
        (WidgetTester tester) async {
      int left = 0;
      await _pump(tester, onLeave: () => left++);

      expect(find.text('Guardar y salir'), findsNothing);
      await tester.tap(find.text('Salir del tablero'));
      await tester.pumpAndSettle();

      expect(left, 1);
    });

    testWidgets('promises only what it can keep', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.textContaining('guardado'), findsNothing);
      expect(find.textContaining('mientras no salgas'), findsOneWidget);
    });

    testWidgets('fits the phone with the text setting turned up',
        (WidgetTester tester) async {
      await _pump(tester, textScale: 1.3);

      expect(tester.takeException(), isNull);
    });
  });
}
