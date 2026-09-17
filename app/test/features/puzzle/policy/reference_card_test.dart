/// What the card shows, decided without a widget.
///
/// The rule text is the pack's and the diagram beside it is ours, so the one
/// thing worth proving is that the two are paired without either being able to
/// invent the other — a line the pack did not carry, or a diagram drawn beside
/// nothing. How long the sheet is stays the pack's call too.
///
/// **The vocabulary line** is where a format names the thing on its board, so
/// it is the one place two formats must not show the same picture — and a cage
/// is a dashed outline, which is the whole point of drawing one beside the line
/// that first says the word.
///
/// **Every format is covered, which is PROC-10 in miniature.** A format whose
/// diagrams nobody wrote would show a card of bare text and no test would say
/// so.
///
/// **A diagram's cage and its outline travel together by sweep, not by
/// assert.** A `const` constructor cannot check `isEmpty` — it is not a
/// constant expression — and an assert would be stripped in release anyway
/// (TYP-2). A diagram with cells and no outline would draw nothing; one with an
/// outline and no cells would name a picture that is not there. The defect
/// behind that pairing: both cage diagrams drew `DashSpec.kenKenCage`, so the
/// picture beside Killer's rule taught KenKen's outline.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/puzzle/spec/cage_outline.dart';
import 'package:akimath_app/features/puzzle/policy/reference_card.dart';
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

KenKenPuzzle _kenKen(List<String> sheet) => KenKenPuzzle(
      board: _board(),
      cages: const <Cage>[],
      tutorialSteps: const <String>[],
      referenceSheet: sheet,
    );

KillerPuzzle _killer(List<String> sheet) => KillerPuzzle(
      board: _board(),
      cages: const <Cage>[],
      tutorialSteps: const <String>[],
      referenceSheet: sheet,
    );

KakuroPuzzle _kakuro(List<String> sheet) => KakuroPuzzle(
      board: _board(),
      runs: const <Run>[],
      tutorialSteps: const <String>[],
      referenceSheet: sheet,
    );

WordSearchPuzzle _sopa(List<String> sheet) => WordSearchPuzzle(
      grid: const <String>['AB', 'CD'],
      words: const <String>['AB'],
      tutorialSteps: const <String>[],
      referenceSheet: sheet,
    );

void main() {
  group('the rows of a reference card', () {
    test('carry the pack\'s lines, verbatim and in order', () {
      final List<ReferenceRow> rows = referenceRows(
        _kenKen(<String>['primero', 'segundo', 'tercero']),
      );

      expect(
        rows.map((ReferenceRow row) => row.text).toList(),
        <String>['primero', 'segundo', 'tercero'],
      );
    });

    test('pair each line with the diagram its format draws for that place', () {
      final List<ReferenceRow> kenKen = referenceRows(
        _kenKen(<String>['a', 'b', 'c']),
      );
      final List<ReferenceRow> kakuro = referenceRows(
        _kakuro(<String>['a', 'b', 'c']),
      );

      expect(kenKen[1].diagram, isNotNull);
      expect(kakuro[1].diagram, isNotNull);
      expect(kenKen[1].diagram, isNot(kakuro[1].diagram));

      expect(kenKen[1].diagram!.cage, isNotEmpty);
      expect(kakuro[1].diagram!.cage, isEmpty);
    });

    test('give a line the pack added no diagram rather than borrowing one', () {
      final List<ReferenceRow> rows = referenceRows(
        _kenKen(<String>['a', 'b', 'c', 'd']),
      );

      expect(rows, hasLength(4));
      expect(rows.last.diagram, isNull);
    });

    test('draw no diagram the pack left no line for', () {
      final List<ReferenceRow> rows = referenceRows(_kenKen(<String>['solo']));

      expect(rows, hasLength(1));
      expect(rows.single.text, 'solo');
    });

    test('are empty when the pack carried no sheet at all', () {
      expect(referenceRows(_kenKen(<String>[])), isEmpty);
    });

    test('cover every format, so a diagram list is never silently absent', () {
      for (final Puzzle puzzle in <Puzzle>[
        _kenKen(<String>['a', 'b', 'c']),
        KillerPuzzle(
          board: _board(),
          cages: const <Cage>[],
          tutorialSteps: const <String>[],
          referenceSheet: const <String>['a', 'b', 'c'],
        ),
        MagicSquarePuzzle(
          board: _board(),
          rowTargets: const <int>[6, 6, 6],
          columnTargets: const <int>[6, 6, 6],
          tutorialSteps: const <String>[],
          referenceSheet: const <String>['a', 'b', 'c'],
        ),
        _kakuro(<String>['a', 'b', 'c']),
        _sopa(<String>['a', 'b', 'c']),
      ]) {
        final List<ReferenceRow> rows = referenceRows(puzzle);
        expect(
          rows.every((ReferenceRow row) => row.diagram != null),
          isTrue,
          reason: '${puzzle.runtimeType} has a line with no diagram',
        );
      }
    });
  });

  group('the title of a reference card', () {
    test('names the format the player is looking at', () {
      expect(referenceCardTitle(_kenKen(<String>[])), 'KENKEN EN CORTO');
      expect(referenceCardTitle(_kakuro(<String>[])), 'KAKURO EN CORTO');
      expect(referenceCardTitle(_sopa(<String>[])), 'SOPA DE LETRAS EN CORTO');
    });

    test('and every format has a name of its own', () {
      final List<String> names = <String>[
        puzzleFormatName(_kenKen(<String>[])),
        puzzleFormatName(KillerPuzzle(
          board: _board(),
          cages: const <Cage>[],
          tutorialSteps: const <String>[],
          referenceSheet: const <String>[],
        )),
        puzzleFormatName(MagicSquarePuzzle(
          board: _board(),
          rowTargets: const <int>[6, 6, 6],
          columnTargets: const <int>[6, 6, 6],
          tutorialSteps: const <String>[],
          referenceSheet: const <String>[],
        )),
        puzzleFormatName(_kakuro(<String>[])),
        puzzleFormatName(_sopa(<String>[])),
      ];

      expect(names.toSet(), hasLength(names.length), reason: '$names');
    });
  });

  group('a diagram', () {
    test('never places a mark outside the grid it declares, where the widget '
        'reading `row * size + column` would drop it in silence', () {
      for (final ReferenceDiagram diagram in allReferenceDiagrams) {
        final int cells = diagram.size * diagram.size;
        expect(diagram.size, greaterThan(0));
        for (final int index in <int>[
          ...diagram.labels.keys,
          ...diagram.shaded,
          ...diagram.highlighted,
          ...diagram.cage,
        ]) {
          expect(index, inInclusiveRange(0, cells - 1),
              reason: 'index $index is off a ${diagram.size}×${diagram.size} grid');
        }
      }
    });

    test('carries a cage label only when it has a cage to hang it on', () {
      for (final ReferenceDiagram diagram in allReferenceDiagrams) {
        if (diagram.cageLabel != null) {
          expect(diagram.cage, isNotEmpty);
        }
      }
    });

    test('draws its cage in an outline, and only when it has a cage', () {
      expect(allReferenceDiagrams, isNotEmpty);

      for (final ReferenceDiagram diagram in allReferenceDiagrams) {
        expect(
          diagram.cage.isEmpty,
          diagram.cageOutline == null,
          reason: 'a diagram of ${diagram.cage.length} caged cells names '
              '${diagram.cageOutline}',
        );
      }
    });

    test('a Killer rule is pictured with the Killer cage, not KenKen\'s', () {
      const List<String> sheet = <String>[
        'Llena cada casilla.',
        'La jaula dice el resultado.',
      ];
      final List<CageOutline> kenKen = referenceRows(_kenKen(sheet))
          .map((ReferenceRow row) => row.diagram?.cageOutline)
          .whereType<CageOutline>()
          .toList();
      final List<CageOutline> killer = referenceRows(_killer(sheet))
          .map((ReferenceRow row) => row.diagram?.cageOutline)
          .whereType<CageOutline>()
          .toList();

      expect(kenKen, <CageOutline>[CageOutline.kenKen]);
      expect(killer, <CageOutline>[CageOutline.killer]);
    });

    test('and the set of them is not empty', () {
      expect(allReferenceDiagrams, isNotEmpty);
    });
  });
}
