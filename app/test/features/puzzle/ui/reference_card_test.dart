/// `Hoja de referencia` on screen.
///
/// **Two ways back is the design's, not an accident**: the corner is where a
/// reader's hand already is and the button is where their eye ends up, so both
/// report the same way out to the same caller.
///
/// **The band of rules scrolls rather than the card growing.** The frozen
/// schema admits six lines and the card is drawn for three, so a player at
/// `textScaler` 1.3 on a small phone is the case that overflows.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/theme.dart';
import 'package:akimath_app/features/puzzle/ui/reference_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<List<int>> _solution = <List<int>>[
  <int>[1, 2, 3],
  <int>[2, 3, 1],
  <int>[3, 1, 2],
];

KenKenPuzzle _puzzle({List<String>? sheet}) => KenKenPuzzle(
      board: const PuzzleBoard.caged(
        size: 3,
        blocked: <Cell>{},
        given: <Cell>{},
        solution: _solution,
      ),
      cages: const <Cage>[],
      tutorialSteps: const <String>[],
      referenceSheet: sheet ??
          const <String>[
            'Llena todas las casillas con números del 1 al 3.',
            'Las jaulas son los grupos con borde punteado.',
            'Nada se repite en su fila ni en su columna.',
          ],
    );

Future<int> _pump(WidgetTester tester, {KenKenPuzzle? puzzle}) async {
  int closed = 0;
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AkiMathTheme.build(),
      home: Scaffold(
        body: ReferenceCard(
          puzzle: puzzle ?? _puzzle(),
          onClose: () => closed++,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return closed;
}

Finder _labelled(String label) => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == label,
      description: 'a control labelled "$label"',
    );

void main() {
  group('the reference card', () {
    testWidgets('is headed with the format it is about',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('KENKEN EN CORTO'), findsOneWidget);
    });

    testWidgets('prints the pack\'s lines and invents none',
        (WidgetTester tester) async {
      await _pump(tester);

      for (final String line in _puzzle().referenceSheet) {
        expect(find.text(line), findsOneWidget);
      }
      expect(
        find.textContaining('jaula').evaluate().length,
        1,
        reason: 'a rule appeared that the pack did not carry',
      );
    });

    testWidgets('draws one diagram beside each line the format has one for',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.byType(ReferenceDiagramView), findsNWidgets(3));
    });

    testWidgets('and a line the format drew nothing for still gets shown',
        (WidgetTester tester) async {
      await _pump(
        tester,
        puzzle: _puzzle(sheet: <String>['una', 'dos', 'tres', 'cuatro']),
      );

      expect(find.text('cuatro'), findsOneWidget);
      expect(find.byType(ReferenceDiagramView), findsNWidgets(3));
    });

    testWidgets('closes from the corner control', (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(_labelled('Cerrar la hoja'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('and from the button at the bottom', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('Volver al tablero'), findsOneWidget);
    });

    testWidgets('reports every way out to the caller', (WidgetTester tester) async {
      int closed = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AkiMathTheme.build(),
          home: Scaffold(
            body: ReferenceCard(puzzle: _puzzle(), onClose: () => closed++),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_labelled('Cerrar la hoja'));
      await tester.pumpAndSettle();
      expect(closed, 1);

      await tester.tap(find.text('Volver al tablero'));
      await tester.pumpAndSettle();
      expect(closed, 2);
    });

    testWidgets('survives a sheet with more text than the card is tall',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AkiMathTheme.build(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: ReferenceCard(
                puzzle: _puzzle(
                  sheet: List<String>.generate(
                    6,
                    (int i) => 'Una regla bastante larga, la número ${i + 1}, '
                        'que ocupa más de un renglón en la tarjeta.',
                  ),
                ),
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
    });
  });
}
