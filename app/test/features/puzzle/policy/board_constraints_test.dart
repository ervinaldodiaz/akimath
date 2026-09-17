/// What a board shows besides its cells, decided without a widget.
///
/// The screen used to reconstruct this from four wildcard `switch` arms, each
/// falling through to an empty list, and the view then asked whether two of
/// those lists were empty to decide what to draw. A sixth format would have
/// compiled, opened and drawn a bare grid. Here the switch is exhaustive over
/// the sealed hierarchy, so the sixth format is a compile error instead — and
/// the sweep at the bottom is the half a compiler cannot do, which is finding 1
/// of `docs/solid/puzzle.md` from the side the compiler cannot reach: a sixth
/// format has to pick a named constructor, because there is no empty one, and
/// the sweep says the list it picked is not empty either.
///
/// The same split covers a cage's **appearance**: `BoardConstraints.cages`
/// demands an outline, so a cage cannot reach the board without one, and the
/// two tests below say the outline each caged format gets is its own. The
/// pairing holds in both directions by a sweep rather than by an assert — a
/// `const` constructor can refuse neither, and an assert would be stripped in
/// release anyway (TYP-2). The compiler owns *a cage cannot be drawn unnamed*;
/// the sweep owns *nothing names an outline it has no cage for*.
///
/// **The two caged leaves are named apart on purpose.** KenKen and Killer are
/// leaves of `CagedPuzzle`, and an arm matching the parent would let a third
/// caged format compile while drawing only the part it shares. That is the
/// defect this file was written for: the screen read the cages off any
/// `CagedPuzzle` and the board widget named `DashSpec.kenKenCage` itself, so
/// the two formats were one drawing. A sixth caged format has to pick a
/// constant of its own, and copying a sibling's is the thing said out loud.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/puzzle/spec/cage_outline.dart';
import 'package:akimath_app/features/puzzle/policy/board_constraints.dart';
import 'package:flutter_test/flutter_test.dart';

const List<List<int>> _threeByThree = <List<int>>[
  <int>[1, 2, 3],
  <int>[2, 3, 1],
  <int>[3, 1, 2],
];

PuzzleBoard _board() => const PuzzleBoard.caged(
      size: 3,
      blocked: <Cell>{},
      given: <Cell>{},
      solution: _threeByThree,
    );

const List<Cage> _cages = <Cage>[
  Cage(cells: <Cell>[Cell(row: 0, col: 0)], operation: '+', target: 1),
];

const List<Run> _runs = <Run>[
  Run(
    cells: <Cell>[Cell(row: 0, col: 0), Cell(row: 0, col: 1)],
    sum: 3,
  ),
];

KenKenPuzzle _kenKen() => KenKenPuzzle(
      board: _board(),
      cages: _cages,
      tutorialSteps: const <String>[],
      referenceSheet: const <String>[],
    );

KillerPuzzle _killer() => KillerPuzzle(
      board: _board(),
      cages: _cages,
      tutorialSteps: const <String>[],
      referenceSheet: const <String>[],
    );

MagicSquarePuzzle _magicSquare() => MagicSquarePuzzle(
      board: _board(),
      rowTargets: const <int>[11, 12, 13],
      columnTargets: const <int>[21, 22, 23],
      tutorialSteps: const <String>[],
      referenceSheet: const <String>[],
    );

KakuroPuzzle _kakuro() => KakuroPuzzle(
      board: _board(),
      runs: _runs,
      tutorialSteps: const <String>[],
      referenceSheet: const <String>[],
    );

/// One puzzle of every format the shared board draws.
///
/// Hand-maintained, and it has to be: nothing in Dart enumerates the leaves of
/// a sealed type at run time. The compiler is what forces a sixth format to be
/// named in `boardConstraints`; this list is what forces it to show something
/// once it is.
List<BoardPuzzle> _everyFormat() => <BoardPuzzle>[
      _kenKen(),
      _killer(),
      _magicSquare(),
      _kakuro(),
    ];

void main() {
  group('what a format asks of the player', () {
    test('a KenKen shows its cages and nothing else', () {
      final BoardConstraints shown = boardConstraints(_kenKen());

      expect(shown.cages, same(_cages));
      expect(shown.outline, CageOutline.kenKen);
      expect(shown.rowTargets, isEmpty);
      expect(shown.columnTargets, isEmpty);
      expect(shown.runs, isEmpty);
    });

    test('a Killer shows its cages, in an outline that is not the KenKen it '
        'otherwise matches', () {
      final BoardConstraints shown = boardConstraints(_killer());

      expect(shown.cages, same(_cages));
      expect(shown.outline, CageOutline.killer);
      expect(shown.outline, isNot(CageOutline.kenKen));
      expect(shown.rowTargets, isEmpty);
      expect(shown.columnTargets, isEmpty);
      expect(shown.runs, isEmpty);
    });

    test('a magic square shows the total each line must reach', () {
      final BoardConstraints shown = boardConstraints(_magicSquare());

      expect(shown.rowTargets, <int>[11, 12, 13]);
      expect(shown.columnTargets, <int>[21, 22, 23]);
      expect(shown.cages, isEmpty);
      expect(shown.outline, isNull);
      expect(shown.runs, isEmpty);
    });

    test('a Kakuro shows its runs and nothing else', () {
      final BoardConstraints shown = boardConstraints(_kakuro());

      expect(shown.runs, same(_runs));
      expect(shown.cages, isEmpty);
      expect(shown.outline, isNull);
      expect(shown.rowTargets, isEmpty);
      expect(shown.columnTargets, isEmpty);
    });
  });

  group('the margin the board makes room for', () {
    test('is asked for by the one format that has targets to put in it', () {
      expect(boardConstraints(_magicSquare()).hasLineTargets, isTrue);

      for (final BoardPuzzle puzzle in <BoardPuzzle>[
        _kenKen(),
        _killer(),
        _kakuro(),
      ]) {
        expect(
          boardConstraints(puzzle).hasLineTargets,
          isFalse,
          reason: '${puzzle.runtimeType} draws no margin',
        );
      }
    });
  });

  group('cages and their outline travel together', () {
    test('every format pairs them, or has neither', () {
      final List<BoardPuzzle> formats = _everyFormat();
      expect(formats, isNotEmpty, reason: 'a sweep over nothing sweeps nothing');

      int caged = 0;
      for (final BoardPuzzle puzzle in formats) {
        final BoardConstraints shown = boardConstraints(puzzle);
        if (shown.outline != null) {
          caged++;
        }
        expect(
          shown.cages.isEmpty,
          shown.outline == null,
          reason: '${puzzle.runtimeType} pairs ${shown.cages.length} cages '
              'with ${shown.outline}',
        );
      }

      expect(caged, 2, reason: 'KenKen and Killer are the caged formats');
    });

    test('and no two caged formats share an outline', () {
      final Set<CageOutline> outlines = <CageOutline>{
        for (final BoardPuzzle puzzle in _everyFormat())
          if (boardConstraints(puzzle).outline case final CageOutline outline)
            outline,
      };

      expect(outlines, hasLength(2));
    });
  });

  group('every format shows something', () {
    test('none of them draws a bare grid', () {
      final List<BoardPuzzle> formats = _everyFormat();
      expect(formats, isNotEmpty, reason: 'a sweep over nothing sweeps nothing');

      int showing = 0;
      for (final BoardPuzzle puzzle in formats) {
        final BoardConstraints shown = boardConstraints(puzzle);
        final bool showsSomething = shown.cages.isNotEmpty ||
            shown.runs.isNotEmpty ||
            shown.hasLineTargets;
        if (showsSomething) {
          showing++;
        }
        expect(
          showsSomething,
          isTrue,
          reason: '${puzzle.runtimeType} shows no constraint at all',
        );
      }

      // ignore: avoid_print
      print('  board constraints · ${formats.length} formats swept → '
          '$showing show a constraint');
    });
  });
}
