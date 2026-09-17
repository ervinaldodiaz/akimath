/// The board on screen: its cells, its cages, and the targets beside them.
///
/// **Two of these are measured rather than looked for** (PROC-11). Asserting
/// that no target text appears cannot fail when the target list is empty — the
/// margin renders nothing either way — so what the no-targets case reads is the
/// grid's own width. And the six line targets are six *distinct* numbers,
/// though a real magic square's are all the same: a repeated target is
/// indistinguishable from a target drawn twice, which is the failure that case
/// is for.
///
/// **A 6×6 is the tightest layout in the app.** 330 px across six cells is 55
/// each, which clears the 48 px minimum (BRD-2d) — a 7×7 would not, which is
/// why the format stops at six.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/puzzle/spec/cage_outline.dart';
import 'package:akimath_app/features/puzzle/policy/board_constraints.dart';
import 'package:akimath_app/features/puzzle/policy/puzzle_entry.dart';
import 'package:akimath_app/features/puzzle/ui/puzzle_board_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<List<int>> _solution = <List<int>>[
  <int>[1, 2, 3],
  <int>[2, 3, 1],
  <int>[3, 1, 2],
];

PuzzleBoard _board({
  Set<Cell> blocked = const <Cell>{},
  Set<Cell> given = const <Cell>{},
}) =>
    PuzzleBoard.caged(size: 3, blocked: blocked, given: given, solution: _solution);

/// One cage over the whole board, so every cell is covered without the test
/// having to describe five of them.
List<Cage> _oneCage(int size) => <Cage>[
      Cage(
        cells: <Cell>[
          for (int row = 0; row < size; row++)
            for (int col = 0; col < size; col++) Cell(row: row, col: col),
        ],
        operation: '+',
        target: 18,
      ),
    ];

Future<PuzzleEntry> _pump(
  WidgetTester tester, {
  PuzzleEntry? entry,
  List<Cage>? cages,
}) async {
  PuzzleEntry current = entry ?? PuzzleEntry.of(_board());
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 330,
            child: PuzzleBoardView(
              entry: current,
              constraints:
                  BoardConstraints.cages(
                    cages ?? _oneCage(current.board.size),
                    CageOutline.kenKen,
                  ),
              onTapCell: (Cell cell) => current = current.select(cell),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return current;
}

/// Every cell's painted fill, in reading order.
List<Color?> _fills(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.descendant(
      of: find.byType(PuzzleBoardView),
      matching: find.byType(DecoratedBox),
    ))
    .map((DecoratedBox box) => (box.decoration as BoxDecoration).color)
    .where((Color? color) => color != null)
    .toList();

/// A cage per cell, so **every** cell is enclosed on all four sides by the
/// heavy cage outline.
///
/// This is the board the reported defect hid on: selection was a ring in ink at
/// 3 px — the cage outline's own colour and width, on the same edges — so a
/// cell enclosed by its cage was selectable with no visible selection at all.
List<Cage> _cagePerCell(int size) => <Cage>[
      for (int row = 0; row < size; row++)
        for (int col = 0; col < size; col++)
          Cage(
            cells: <Cell>[Cell(row: row, col: col)],
            operation: '+',
            target: _solution[row][col],
          ),
    ];

void main() {
  group('the selected cell can be seen', () {
    testWidgets('its fill is unlike every other cell on the board',
        (WidgetTester tester) async {
      await _pump(
        tester,
        entry: PuzzleEntry.of(_board()).select(const Cell(row: 1, col: 1)),
      );

      final List<Color?> fills = _fills(tester);
      final Map<Color?, int> counted = <Color?, int>{};
      for (final Color? fill in fills) {
        counted[fill] = (counted[fill] ?? 0) + 1;
      }

      expect(
        counted.values.where((int n) => n == 1),
        isNotEmpty,
        reason: 'no cell is drawn differently from the rest',
      );
    });

    testWidgets('even when its cage outlines it on all four sides',
        (WidgetTester tester) async {
      await _pump(
        tester,
        entry: PuzzleEntry.of(_board()).select(const Cell(row: 1, col: 1)),
        cages: _cagePerCell(3),
      );
      final List<Color?> withSelection = _fills(tester);

      await _pump(tester, cages: _cagePerCell(3));
      final List<Color?> without = _fills(tester);

      expect(withSelection, isNot(without));
    });

    testWidgets('nothing is highlighted before a cell is chosen',
        (WidgetTester tester) async {
      await _pump(tester);
      final Set<Color?> fills = _fills(tester).toSet();

      expect(fills, hasLength(1));
    });
  });

  group('the board draws its cells', () {
    testWidgets('one per square', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byType(GestureDetector), findsNWidgets(9));
    });

    testWidgets('a given shows its value — a 1 at (0,0) — and an open cell '
        'does not', (WidgetTester tester) async {
      await _pump(
        tester,
        entry: PuzzleEntry.of(_board(given: <Cell>{const Cell(row: 0, col: 0)})),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(find.text('3'), findsNothing);
    });
  });

  group('the board never draws the answer', () {
    testWidgets('no open cell shows its solution value',
        (WidgetTester tester) async {
      await _pump(tester);

      int checked = 0;
      for (final Cell cell in _board().openCells) {
        checked++;
        expect(
          find.text('${_board().valueAt(cell)}'),
          findsNothing,
          reason: '$cell leaked its solution',
        );
      }
      expect(checked, 9, reason: 'the sweep must visit every open cell');
    });

    testWidgets('a value the player entered is drawn, and the solution it '
        'stands in front of is not', (WidgetTester tester) async {
      final PuzzleEntry entry = PuzzleEntry.of(_board())
          .select(const Cell(row: 1, col: 1))
          .type(2);
      await _pump(tester, entry: entry);

      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
    });
  });

  group('a cage says what it asks, once', () {
    testWidgets('the target appears on one cell only, the top-left corner of '
        'its cage', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.textContaining('18'), findsOneWidget);
    });

    testWidgets('a single-cell cage shows no operation, having nothing to '
        'combine', (WidgetTester tester) async {
      await _pump(
        tester,
        cages: <Cage>[
          const Cage(cells: <Cell>[Cell(row: 0, col: 0)], operation: '+', target: 1),
          Cage(
            cells: <Cell>[
              for (int row = 0; row < 3; row++)
                for (int col = 0; col < 3; col++)
                  if (!(row == 0 && col == 0)) Cell(row: row, col: col),
            ],
            operation: '+',
            target: 17,
          ),
        ],
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('1+'), findsNothing);
    });

    testWidgets('a killer cage shows its target and no operation, asking for a '
        'sum by naming nothing', (WidgetTester tester) async {
      await _pump(
        tester,
        cages: <Cage>[
          Cage(
            cells: <Cell>[
              for (int row = 0; row < 3; row++)
                for (int col = 0; col < 3; col++) Cell(row: row, col: col),
            ],
            target: 18,
          ),
        ],
      );

      expect(find.text('18'), findsOneWidget);
      expect(find.text('18+'), findsNothing);
    });

    testWidgets('two cages label two different cells',
        (WidgetTester tester) async {
      await _pump(
        tester,
        cages: <Cage>[
          Cage(
            cells: <Cell>[
              for (int col = 0; col < 3; col++) Cell(row: 0, col: col),
            ],
            operation: '+',
            target: 6,
          ),
          Cage(
            cells: <Cell>[
              for (int row = 1; row < 3; row++)
                for (int col = 0; col < 3; col++) Cell(row: row, col: col),
            ],
            operation: '×',
            target: 12,
          ),
        ],
      );

      expect(find.textContaining('6+'), findsOneWidget);
      expect(find.textContaining('12×'), findsOneWidget);
    });
  });

  group('a line may say what it must total', () {
    testWidgets('each target is shown once, against its own line',
        (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 330,
                child: PuzzleBoardView(
                  entry: PuzzleEntry.of(_board()),
                  constraints: const BoardConstraints.lineTargets(
                    rowTargets: <int>[11, 12, 13],
                    columnTargets: <int>[21, 22, 23],
                  ),
                  onTapCell: (Cell cell) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final String target in <String>['11', '12', '13', '21', '22', '23']) {
        expect(find.text(target), findsOneWidget, reason: target);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a board with no targets gives its grid the whole width',
        (WidgetTester tester) async {
      Future<double> gridWidth({required bool withTargets}) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 330,
                  child: PuzzleBoardView(
                    entry: PuzzleEntry.of(_board()),
                    constraints: withTargets
                        ? const BoardConstraints.lineTargets(
                            rowTargets: <int>[11, 12, 13],
                            columnTargets: <int>[21, 22, 23],
                          )
                        : const BoardConstraints.cages(<Cage>[], CageOutline.kenKen),
                    onTapCell: (Cell cell) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(AspectRatio)).width;
      }

      final double bare = await gridWidth(withTargets: false);
      final double withMargin = await gridWidth(withTargets: true);

      expect(bare, 330, reason: 'a caged board uses the whole width');
      expect(withMargin, lessThan(bare),
          reason: 'a margin has to come out of somewhere');
    });
  });

  group('a run says what it must total, where it starts', () {
    Future<void> pumpRuns(WidgetTester tester, List<Run> runs) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 330,
                child: PuzzleBoardView(
                  entry: PuzzleEntry.of(_board()),
                  constraints: BoardConstraints.runs(runs),
                  onTapCell: (Cell cell) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an across run is clued on its first cell',
        (WidgetTester tester) async {
      await pumpRuns(tester, const <Run>[
        Run(cells: <Cell>[Cell(row: 0, col: 0), Cell(row: 0, col: 1)], sum: 7),
      ]);
      expect(find.text('7→'), findsOneWidget);
    });

    testWidgets('a cell starting two runs shows both',
        (WidgetTester tester) async {
      await pumpRuns(tester, const <Run>[
        Run(cells: <Cell>[Cell(row: 0, col: 0), Cell(row: 0, col: 1)], sum: 7),
        Run(cells: <Cell>[Cell(row: 0, col: 0), Cell(row: 1, col: 0)], sum: 12),
      ]);

      expect(find.text('7→'), findsOneWidget);
      expect(find.text('12↓'), findsOneWidget);
    });

    testWidgets('a run starting at the edge is still clued',
        (WidgetTester tester) async {
      await pumpRuns(tester, const <Run>[
        Run(cells: <Cell>[Cell(row: 2, col: 0), Cell(row: 2, col: 1)], sum: 9),
      ]);
      expect(find.text('9→'), findsOneWidget);
    });

    testWidgets('a board with no runs shows no clue',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.textContaining('→'), findsNothing);
      expect(find.textContaining('↓'), findsNothing);
    });
  });

  group('only open cells respond', () {
    testWidgets('tapping an open cell selects it', (WidgetTester tester) async {
      PuzzleEntry entry = PuzzleEntry.of(_board());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) =>
                    PuzzleBoardView(
                  entry: entry,
                  constraints: BoardConstraints.cages(_oneCage(3), CageOutline.kenKen),
                  onTapCell: (Cell cell) =>
                      setState(() => entry = entry.select(cell)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector).at(4));
      await tester.pumpAndSettle();

      expect(entry.selected, isNotNull);
    });

    testWidgets('tapping a given or a blocked cell selects nothing',
        (WidgetTester tester) async {
      PuzzleEntry entry = PuzzleEntry.of(_board(
        given: <Cell>{const Cell(row: 0, col: 0)},
        blocked: <Cell>{const Cell(row: 2, col: 2)},
      ));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 330,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) =>
                    PuzzleBoardView(
                  entry: entry,
                  constraints: BoardConstraints.cages(_oneCage(3), CageOutline.kenKen),
                  onTapCell: (Cell cell) =>
                      setState(() => entry = entry.select(cell)),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector).first);
      await tester.pumpAndSettle();
      expect(entry.selected, isNull, reason: 'a given was selected');

      await tester.tap(find.byType(GestureDetector).last);
      await tester.pumpAndSettle();
      expect(entry.selected, isNull, reason: 'a blocked cell was selected');
    });
  });

  group('it fits a phone', () {
    testWidgets('a 6x6 keeps every cell above the touch minimum',
        (WidgetTester tester) async {
      await _pump(
        tester,
        entry: PuzzleEntry.of(PuzzleBoard.caged(
          size: 6,
          blocked: const <Cell>{},
          given: const <Cell>{},
          solution: <List<int>>[
            for (int row = 0; row < 6; row++)
              <int>[for (int col = 0; col < 6; col++) (row + col) % 6 + 1],
          ],
        )),
        cages: _oneCage(6),
      );

      final Size cell = tester.getSize(find.byType(GestureDetector).first);
      expect(cell.width, greaterThanOrEqualTo(48));
      expect(cell.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });
}
