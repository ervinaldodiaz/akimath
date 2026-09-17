/// What a paused board says about itself, decided without a widget.
///
/// **It reads as a count and never as a clock.**
/// `quiet_while_you_solve_test.dart` forbids anything that reads as a clock on
/// a solving surface, and a paused board is mid-solve — the design draws
/// `Pausa` with a cell count and a format name and no elapsed time at all. The
/// last case holds the *type* to it: there is nowhere in `PauseSummary` to put
/// a duration.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/features/puzzle/policy/pause.dart';
import 'package:akimath_app/features/puzzle/policy/puzzle_entry.dart';
import 'package:flutter_test/flutter_test.dart';

PuzzleBoard _board({Set<Cell> given = const <Cell>{}}) => PuzzleBoard.caged(
      size: 3,
      blocked: const <Cell>{},
      given: given,
      solution: const <List<int>>[
        <int>[1, 2, 3],
        <int>[2, 3, 1],
        <int>[3, 1, 2],
      ],
    );

KenKenPuzzle _kenKen({Set<Cell> given = const <Cell>{}}) => KenKenPuzzle(
      board: _board(given: given),
      cages: const <Cage>[],
      tutorialSteps: const <String>[],
      referenceSheet: const <String>[],
    );

void main() {
  group('what a paused board says about itself', () {
    test('counts the cells the player filled, out of the ones that are theirs',
        () {
      final PuzzleEntry entry = PuzzleEntry.of(_board())
          .select(const Cell(row: 0, col: 0))
          .type(1)
          .select(const Cell(row: 1, col: 1))
          .type(3);

      final PauseSummary summary = pauseSummary(_kenKen(), entry);

      expect(summary.filled, 2);
      expect(summary.total, 9);
    });

    test('and a given is not one of them: counting the question as progress '
        'would credit a player with work they have not done', () {
      final Set<Cell> given = <Cell>{const Cell(row: 0, col: 0)};
      final PuzzleEntry entry = PuzzleEntry.of(_board(given: given));

      final PauseSummary summary = pauseSummary(_kenKen(given: given), entry);

      expect(summary.filled, 0);
      expect(summary.total, 8);
    });

    test('names the format and the board it is on', () {
      final PauseSummary summary =
          pauseSummary(_kenKen(), PuzzleEntry.of(_board()));

      expect(summary.formatName, 'KENKEN');
      expect(summary.sizeLabel, '3 × 3');
    });

    test('reads as a count and never as a clock', () {
      final PauseSummary summary =
          pauseSummary(_kenKen(), PuzzleEntry.of(_board()));

      final RegExp clock =
          RegExp(r'\b\d+:[0-5]\d\b|\b\d+([.,]\d+)?\s*(s|seg|segundos|min)\b');
      for (final String reading in <String>[
        summary.formatName,
        summary.sizeLabel,
        '${summary.filled}',
        '${summary.total}',
      ]) {
        expect(clock.hasMatch(reading), isFalse, reason: reading);
      }
    });
  });
}
