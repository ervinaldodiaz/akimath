/// A KenKen played through the shared board screen.
///
/// **Working on a board is practice.** The streak counts days practised and a
/// round records on submit, right or wrong; a board's analogue of submitting is
/// putting a value on it.
///
/// **The pad offers only what the board can hold.** Nine keys on a board that
/// admits three: the six that cannot act used to look identical to the three
/// that can and simply did nothing, which is what the preferences screen
/// already argues against.
///
/// **Pausing covers, it does not erase** — *tablero tapado, no borrado*. The
/// entry is the `State`'s and pausing only changes what is drawn, which is the
/// whole reason this is one screen and not two routes.
///
/// **A cage is drawn in its own format's outline.** The defect: both call sites
/// named `DashSpec.kenKenCage` themselves, so Killer — which routes through the
/// same widget — drew KenKen's `6 4` dash. `DashSpec.killerCage` reached no
/// screen, and the only test that read its round cap read a constant rather
/// than a painter. Measured here before the fix: `6.0 on / 4.0 off, butt cap`.
///
/// **One case is named for what it checks**, which is not what it was called.
/// It read *"a key pressed while it is open does nothing"* and pressed no key —
/// it could not: nothing is mounted to press, which is the whole claim. What
/// stood in for the behaviour was `expect(solved, 0)` over an `int` the harness
/// had snapshotted at zero, so the line held for every input and the name
/// advertised a behavioural check nobody had written (PROC-11, twice over). The
/// absence assertion carries the load, and it is enough: it goes red both when
/// the `if (!_rulesOpen)` guard is removed **and** when a pad is left mounted
/// with its keys merely disabled, because a disabled key is still a
/// `KeypadKeyView`. Adding a press back is not available — a tap needs a target
/// — and a tap-if-present would be the same vacuous line in a different shape.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/painting/spec/dash_spec.dart';
import 'package:akimath_app/design/puzzle/cage_edge_painter.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/features/puzzle/ui/puzzle_board_view.dart';
import 'package:akimath_app/features/puzzle/ui/puzzle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<List<int>> _solution = <List<int>>[
  <int>[1, 2, 3],
  <int>[2, 3, 1],
  <int>[3, 1, 2],
];

KenKenPuzzle _puzzle() => KenKenPuzzle(
      board: const PuzzleBoard.caged(
        size: 3,
        blocked: <Cell>{},
        given: <Cell>{},
        solution: _solution,
      ),
      cages: <Cage>[
        Cage(
          cells: <Cell>[
            for (int row = 0; row < 3; row++)
              for (int col = 0; col < 3; col++) Cell(row: row, col: col),
          ],
          operation: '+',
          target: 18,
        ),
      ],
      tutorialSteps: const <String>['Cada fila lleva 1, 2 y 3.'],
      referenceSheet: const <String>[
        'Ningún número se repite en su fila ni en su columna.',
        'La esquina de la jaula dice el resultado.',
      ],
    );

/// The same board, in the format that asks for a sum and names no operation.
KillerPuzzle _killer() => KillerPuzzle(
      board: const PuzzleBoard.caged(
        size: 3,
        blocked: <Cell>{},
        given: <Cell>{},
        solution: _solution,
      ),
      cages: <Cage>[
        Cage(
          cells: <Cell>[
            for (int row = 0; row < 3; row++)
              for (int col = 0; col < 3; col++) Cell(row: row, col: col),
          ],
          target: 18,
        ),
      ],
      tutorialSteps: const <String>['Cada fila lleva 1, 2 y 3.'],
      referenceSheet: const <String>[
        'Ningún número se repite en su fila ni en su columna.',
        'La esquina de la jaula dice la suma.',
      ],
    );

/// Every dash pattern the board's cage painters were handed, spelled out.
///
/// Spelled rather than compared as objects: `DashSpec` carries no `toString`,
/// so a set of instances reports as `Instance of 'DashSpec'` on both sides and
/// a red run says nothing about which pattern was drawn.
Set<String> _cageDashes(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(PuzzleBoardView),
      matching: find.byType(CustomPaint),
    ))
    .map((CustomPaint paint) => paint.foregroundPainter)
    .whereType<CageEdgePainter>()
    .map((CageEdgePainter painter) => _spell(painter.outline.dash))
    .toSet();

String _spell(DashSpec dash) =>
    '${dash.on} on / ${dash.off} off, ${dash.cap.name} cap';

Future<void> _pumpPuzzle(WidgetTester tester, BoardPuzzle puzzle) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: PuzzleScreen(puzzle: puzzle)));
  await tester.pumpAndSettle();
}

/// Pumps the screen and hands back **a reading of the solve counter**, not a
/// copy of it.
///
/// It returned a bare `int` until 2026-08-29 — a snapshot taken before the test
/// had touched anything, so it was always zero and every `expect(solved, …)`
/// downstream of it was `expect(0, 0)` (PROC-11). A closure is read at the
/// moment it is called, which is the shape `word_search_screen_test.dart`'s
/// `_pumpCountingPractice` already had.
Future<int Function()> _pump(WidgetTester tester, {VoidCallback? onClose}) async {
  int solved = 0;
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: PuzzleScreen(
        puzzle: _puzzle(),
        onClose: onClose,
        onSolved: () => solved++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => solved;
}

Future<void> _press(WidgetTester tester, String id) async {
  await tester.tap(find.byWidgetPredicate(
    (Widget w) => w is KeypadKeyView && w.data.id == id,
  ));
  await tester.pump();
}

/// The control carrying an accessible label.
///
/// Matched on the `Semantics` widget rather than through the semantics tree:
/// `bySemanticsLabel` needs a `SemanticsHandle`, and a handle taken in a helper
/// outlives the end-of-test verification that insists it be disposed. This
/// asserts the same thing — the label is on the control — without that dance.
Finder _labelled(String label) => find.byWidgetPredicate(
      (Widget w) => w is Semantics && w.properties.label == label,
    );

/// A value **on the board**, not on the keypad.
///
/// The pad's own faces are 1 to 9, so a bare `find.text('2')` matches a key and
/// says nothing about the grid. Every board assertion is scoped, and the first
/// draft of this file was green for the wrong reason before that.
Finder _onBoard(String value) => find.descendant(
      of: find.byType(PuzzleBoardView),
      matching: find.text(value),
    );

/// Taps the cell at [row], [col] — the board lays them out in reading order.
///
/// Scoped to the board for the same reason [_onBoard] is: the header buttons
/// and every keypad key are gesture detectors too, so an unscoped index taps
/// something else entirely and the test passes having exercised nothing.
Future<void> _tapCell(WidgetTester tester, int row, int col) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(PuzzleBoardView),
          matching: find.byType(GestureDetector),
        )
        .at(row * 3 + col),
  );
  await tester.pump();
}

/// Whether a key is offered as usable.
bool _available(WidgetTester tester, String id) => tester
    .widget<KeypadKeyView>(find.byWidgetPredicate(
      (Widget w) => w is KeypadKeyView && w.data.id == id,
    ))
    .available;

void main() {
  group('working on a board is practice', () {
    testWidgets('the first value entered reports it, once',
        (WidgetTester tester) async {
      int practised = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PuzzleScreen(
            puzzle: _puzzle(),
            onPractised: () => practised++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(practised, 0, reason: 'opening a puzzle is not practice');

      await _tapCell(tester, 0, 0);
      expect(practised, 0, reason: 'selecting a cell is not practice');

      await _press(tester, '1');
      expect(practised, 1);

      await _tapCell(tester, 0, 1);
      await _press(tester, '2');
      expect(practised, 1, reason: 'the day is recorded once, not per digit');
    });

    testWidgets('a key the board cannot hold is not practice, asserting '
        'nothing about the puzzle', (WidgetTester tester) async {
      int practised = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PuzzleScreen(
            puzzle: _puzzle(),
            onPractised: () => practised++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapCell(tester, 0, 0);
      await _press(tester, '9');
      expect(practised, 0);

      await _press(tester, '1');
      expect(practised, 1, reason: 'a value it can hold still counts');
    });

    testWidgets('a value typed with no cell selected is not practice',
        (WidgetTester tester) async {
      int practised = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PuzzleScreen(
            puzzle: _puzzle(),
            onPractised: () => practised++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _press(tester, '1');
      expect(practised, 0);
    });
  });

  group('the pad offers only what the board can hold', () {
    testWidgets('a 3x3 offers three digits', (WidgetTester tester) async {
      await _pump(tester);

      for (final String digit in <String>['1', '2', '3']) {
        expect(_available(tester, digit), isTrue, reason: '$digit should work');
      }
      for (final String digit in <String>['4', '5', '6', '7', '8', '9']) {
        expect(_available(tester, digit), isFalse, reason: '$digit cannot act');
      }
      expect(_available(tester, 'backspace'), isTrue,
          reason: 'backspace always can');
    });

    testWidgets('pressing an unavailable key still enters nothing, because '
        'only the presentation changed', (WidgetTester tester) async {
      await _pump(tester);
      await _tapCell(tester, 0, 0);
      await _press(tester, '7');
      expect(_onBoard('7'), findsNothing);
    });
  });

  group('the screen composes the board and the pad it was built for', () {
    testWidgets('both are there — the board, and the 5×2 pad whose missing '
        'submit key is how a board announces itself finished',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byType(PuzzleBoardView), findsOneWidget);
      expect(find.byType(KeypadKeyView), findsNWidgets(10));
      expect(
        find.byWidgetPredicate(
            (Widget w) => w is KeypadKeyView && w.data.id == 'submit'),
        findsNothing,
      );
    });
  });

  group('playing it', () {
    testWidgets('a digit lands in the selected cell',
        (WidgetTester tester) async {
      await _pump(tester);
      await _tapCell(tester, 0, 0);
      await _press(tester, '1');

      expect(_onBoard('1'), findsOneWidget);
    });

    testWidgets('backspace clears it', (WidgetTester tester) async {
      await _pump(tester);
      await _tapCell(tester, 1, 1);
      await _press(tester, '2');
      await _press(tester, 'backspace');

      expect(_onBoard('2'), findsNothing);
    });

    testWidgets('a digit with nothing selected does nothing',
        (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, '1');
      expect(_onBoard('1'), findsNothing);
    });
  });

  group('finishing', () {
    testWidgets('solving the last cell reports it once',
        (WidgetTester tester) async {
      final int Function() solved = await _pump(tester);

      for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 3; col++) {
          await _tapCell(tester, row, col);
          await _press(tester, '${_solution[row][col]}');
        }
      }

      expect(solved(), 1);

      await _tapCell(tester, 0, 0);
      await _press(tester, '1');
      expect(solved(), 1);
    });

    testWidgets('a full but wrong board reports nothing, every cell a 1',
        (WidgetTester tester) async {
      final int Function() solved = await _pump(tester);

      for (int row = 0; row < 3; row++) {
        for (int col = 0; col < 3; col++) {
          await _tapCell(tester, row, col);
          await _press(tester, '1');
        }
      }

      expect(solved(), 0);
    });
  });

  group('the way out and the rules', () {
    testWidgets('there is exactly one way out', (WidgetTester tester) async {
      bool closed = false;
      await _pump(tester, onClose: () => closed = true);

      await tester.tap(_labelled('Salir'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('the rules come from the pack and are shown on demand',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.textContaining('se repite'), findsNothing);

      await tester.tap(_labelled('Cómo se juega'));
      await tester.pumpAndSettle();
      expect(find.textContaining('se repite'), findsOneWidget);
    });

    testWidgets('and open, the sheet is a card over the board rather than text '
        'pushed above it', (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(_labelled('Cómo se juega'));
      await tester.pumpAndSettle();

      expect(find.text('KENKEN EN CORTO'), findsOneWidget);
      expect(find.byType(PuzzleBoardView), findsNothing,
          reason: 'the board is replaced rather than squeezed');
      expect(find.byType(KeypadKeyView), findsNothing,
          reason: 'the pad goes with the board it types into');
    });

    testWidgets('and with a cell selected, opening it leaves no key at all',
        (WidgetTester tester) async {
      await _pump(tester);
      await _tapCell(tester, 0, 0);
      await tester.tap(_labelled('Cómo se juega'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((Widget w) => w is KeypadKeyView),
          findsNothing);
    });
  });

  group('pausing', () {
    testWidgets('covers the board and says which one it is',
        (WidgetTester tester) async {
      await _pump(tester);

      await tester.tap(_labelled('Pausar'));
      await tester.pumpAndSettle();

      expect(find.text('EN PAUSA'), findsOneWidget);
      expect(find.byType(PuzzleBoardView), findsNothing);
    });

    testWidgets('does not erase what was entered', (WidgetTester tester) async {
      await _pump(tester);
      await _tapCell(tester, 0, 0);
      await _press(tester, '1');
      expect(_onBoard('1'), findsOneWidget);

      await tester.tap(_labelled('Pausar'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('DE 9 CELDAS'), findsOneWidget);

      await tester.tap(find.text('Reanudar'));
      await tester.pumpAndSettle();

      expect(find.byType(PuzzleBoardView), findsOneWidget);
      expect(_onBoard('1'), findsOneWidget);
    });

    testWidgets('and leaving from it is the board\'s own way out',
        (WidgetTester tester) async {
      bool closed = false;
      await _pump(tester, onClose: () => closed = true);

      await tester.tap(_labelled('Pausar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir del tablero'));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });
  });

  group('a cage is drawn in its own format\'s outline', () {
    testWidgets('a KenKen board draws the KenKen dash',
        (WidgetTester tester) async {
      await _pumpPuzzle(tester, _puzzle());

      expect(_cageDashes(tester), <String>{_spell(DashSpec.kenKenCage)});
    });

    testWidgets('a Killer board draws the Killer dash, which reads as dots',
        (WidgetTester tester) async {
      await _pumpPuzzle(tester, _killer());

      expect(_cageDashes(tester), <String>{_spell(DashSpec.killerCage)});
      expect(
        _cageDashes(tester).single,
        contains('round cap'),
        reason: 'the round cap is what makes a `2 5` pattern read as dots',
      );
    });
  });
}
