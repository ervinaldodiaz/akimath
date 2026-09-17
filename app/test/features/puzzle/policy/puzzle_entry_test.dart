/// A board's entry — what a tap and a digit mean — decided without a widget.
///
/// **The domain is the board's own, not its size.** Deriving it from the size
/// is the assumption two caged formats hid: it refuses 4 through 9, every digit
/// above the third, which is most of what a magic square is made of.
///
/// **It says nothing about which cell is wrong** (design D4). A grid that
/// flagged each mistake as it was made would let a player brute-force it one
/// digit at a time, and the solution is on the device only so that grading
/// works offline — so a wrong value comes back as entered, neither corrected
/// nor marked.
library;

import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/features/puzzle/policy/puzzle_entry.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 3×3 Latin square, with one cell given and one blocked so every kind of
/// cell is present in every test.
PuzzleBoard _board({
  Set<Cell> blocked = const <Cell>{},
  Set<Cell> given = const <Cell>{},
}) =>
    PuzzleBoard.caged(
      size: 3,
      blocked: blocked,
      given: given,
      solution: const <List<int>>[
        <int>[1, 2, 3],
        <int>[2, 3, 1],
        <int>[3, 1, 2],
      ],
    );

/// Fills every open cell with its solution value.
PuzzleEntry _solve(PuzzleEntry entry) {
  PuzzleEntry current = entry;
  for (final Cell cell in entry.board.openCells) {
    current = current.select(cell).type(entry.board.valueAt(cell));
  }
  return current;
}

void main() {
  group('a digit goes where the player is looking', () {
    test('into the selected cell, and nowhere else', () {
      final PuzzleEntry entry =
          PuzzleEntry.of(_board()).select(const Cell(row: 1, col: 1)).type(3);

      expect(entry.valueAt(const Cell(row: 1, col: 1)), 3);
      expect(entry.filled, hasLength(1));
    });

    test('a second digit replaces the first', () {
      final PuzzleEntry entry = PuzzleEntry.of(_board())
          .select(const Cell(row: 0, col: 0))
          .type(1)
          .type(2);

      expect(entry.valueAt(const Cell(row: 0, col: 0)), 2);
      expect(entry.filled, hasLength(1));
    });

    test('clearing empties it', () {
      final PuzzleEntry entry = PuzzleEntry.of(_board())
          .select(const Cell(row: 0, col: 0))
          .type(1)
          .clear();

      expect(entry.valueAt(const Cell(row: 0, col: 0)), isNull);
      expect(entry.filled, isEmpty);
    });

    test('a digit with nothing selected changes nothing, rather than landing '
        'somewhere the player is not looking', () {
      final PuzzleEntry entry = PuzzleEntry.of(_board()).type(2);
      expect(entry.filled, isEmpty);
      expect(entry.selected, isNull);
    });

    test('clearing with nothing selected changes nothing', () {
      expect(PuzzleEntry.of(_board()).clear().filled, isEmpty);
    });
  });

  group('the domain is the board\'s, not its size', () {
    /// A 3×3 magic square: three cells across, nine distinct values.
    PuzzleBoard magic() => const PuzzleBoard(
          size: 3,
          blocked: <Cell>{},
          given: <Cell>{},
          solution: <List<int>>[
            <int>[2, 7, 6],
            <int>[9, 5, 1],
            <int>[4, 3, 8],
          ],
          highestValue: 9,
        );

    test('a magic square accepts every digit up to nine', () {
      for (final int value in <int>[1, 5, 7, 9]) {
        final PuzzleEntry entry = PuzzleEntry.of(magic())
            .select(const Cell(row: 0, col: 0))
            .type(value);
        expect(entry.valueAt(const Cell(row: 0, col: 0)), value,
            reason: '$value was refused');
      }
    });

    test('and still refuses ten', () {
      final PuzzleEntry entry =
          PuzzleEntry.of(magic()).select(const Cell(row: 0, col: 0)).type(10);
      expect(entry.filled, isEmpty);
    });

    test('a caged board of the same size still stops at three, since only the '
        'domain differs', () {
      final PuzzleEntry entry = PuzzleEntry.of(_board())
          .select(const Cell(row: 0, col: 0))
          .type(7);
      expect(entry.filled, isEmpty);
    });

    test('a magic square is solved by its own values', () {
      PuzzleEntry entry = PuzzleEntry.of(magic());
      for (final Cell cell in magic().openCells) {
        entry = entry.select(cell).type(magic().valueAt(cell));
      }
      expect(entry.isSolved, isTrue);
    });
  });

  group('only a value the board could hold is accepted', () {
    test('a digit outside the domain is refused, because it is not a wrong '
        'answer but no answer at all', () {
      for (final int value in <int>[0, -1, 4, 9]) {
        final PuzzleEntry entry = PuzzleEntry.of(_board())
            .select(const Cell(row: 0, col: 0))
            .type(value);
        expect(entry.filled, isEmpty, reason: '$value was accepted');
      }
    });

    test('every digit inside the domain is accepted, so a check that refused '
        'everything is not enough', () {
      for (final int value in <int>[1, 2, 3]) {
        final PuzzleEntry entry = PuzzleEntry.of(_board())
            .select(const Cell(row: 0, col: 0))
            .type(value);
        expect(entry.valueAt(const Cell(row: 0, col: 0)), value);
      }
    });
  });

  group('some cells are not the player’s to fill', () {
    test('a given cannot be selected or replaced', () {
      const Cell given = Cell(row: 0, col: 0);
      final PuzzleEntry entry =
          PuzzleEntry.of(_board(given: <Cell>{given})).select(given).type(2);

      expect(entry.selected, isNull);
      expect(entry.valueAt(given), 1, reason: 'the given value still stands');
    });

    test('a blocked cell cannot be selected', () {
      const Cell blocked = Cell(row: 2, col: 2);
      final PuzzleEntry entry = PuzzleEntry.of(_board(blocked: <Cell>{blocked}))
          .select(blocked)
          .type(2);

      expect(entry.selected, isNull);
      expect(entry.valueAt(blocked), isNull);
    });

    test('a cell off the board cannot be selected', () {
      final PuzzleEntry entry =
          PuzzleEntry.of(_board()).select(const Cell(row: 9, col: 0));
      expect(entry.selected, isNull);
    });

    test('neither is counted among the cells to fill', () {
      final PuzzleBoard board = _board(
        blocked: <Cell>{const Cell(row: 2, col: 2)},
        given: <Cell>{const Cell(row: 0, col: 0)},
      );
      expect(board.openCells, hasLength(7));
    });
  });

  group('finished means correct, not merely full', () {
    test('every open cell right is solved', () {
      expect(_solve(PuzzleEntry.of(_board())).isSolved, isTrue);
    });

    test('full but one wrong is not solved, or the player would be grading '
        'the board', () {
      final PuzzleEntry entry = _solve(PuzzleEntry.of(_board()))
          .select(const Cell(row: 2, col: 2))
          .type(1);

      expect(entry.isFull, isTrue);
      expect(entry.isSolved, isFalse);
    });

    test('partly filled is not solved', () {
      final PuzzleEntry entry =
          PuzzleEntry.of(_board()).select(const Cell(row: 0, col: 0)).type(1);

      expect(entry.isFull, isFalse);
      expect(entry.isSolved, isFalse);
    });

    test('a board of only givens is solved before it starts, which is the '
        'right answer and not an accident to guard against', () {
      final PuzzleBoard board = _board(given: <Cell>{
        for (int row = 0; row < 3; row++)
          for (int col = 0; col < 3; col++) Cell(row: row, col: col),
      });
      expect(PuzzleEntry.of(board).isSolved, isTrue);
    });

    test('givens count toward the answer without being entered', () {
      final PuzzleBoard board = _board(given: <Cell>{const Cell(row: 0, col: 0)});
      expect(_solve(PuzzleEntry.of(board)).isSolved, isTrue);
    });
  });

  group('it says nothing about which cell is wrong', () {
    test('the entry exposes no per-cell verdict', () {
      final PuzzleEntry wrong = PuzzleEntry.of(_board())
          .select(const Cell(row: 0, col: 0))
          .type(3);

      expect(wrong.valueAt(const Cell(row: 0, col: 0)), 3);
      expect(wrong.isSolved, isFalse);
    });
  });
}
