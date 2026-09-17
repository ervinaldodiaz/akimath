import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/content/model/word_grid.dart';
import 'package:akimath_app/features/puzzle/policy/word_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frozen golden's grid.
const List<String> _grid = <String>[
  'SUMAX',
  'CYZWB',
  'EDFGH',
  'RIJKL',
  'ONPQT',
];

WordSearchPuzzle _puzzle({List<String> words = const <String>['SUMA', 'CERO']}) =>
    WordSearchPuzzle(
      grid: _grid,
      words: words,
      tutorialSteps: const <String>['Busca las palabras.'],
      referenceSheet: const <String>['Van en ocho direcciones.'],
    );

List<Cell> _line(int row, int col, int dRow, int dCol, int length) => <Cell>[
      for (int i = 0; i < length; i++)
        Cell(row: row + dRow * i, col: col + dCol * i),
    ];

void main() {
  group('a word reads any way it is written', () {
    test('along, and back', () {
      expect(containsWord(_grid, 'SUMA'), isTrue);
      expect(containsWord(_grid, 'AMUS'), isTrue, reason: 'the same run, backwards');
    });

    test('down, the way C-E-R-O reads from row 1 of column 0', () {
      expect(containsWord(_grid, 'CERO'), isTrue);
    });

    test('up', () {
      expect(containsWord(_grid, 'OREC'), isTrue);
    });

    test('each of the eight directions in turn, so a word written in one the '
        'author did not happen to use is not refused', () {
      const List<String> plain = <String>['ABC', 'DEF', 'GHI'];
      const Map<String, String> byDirection = <String, String>{
        'along': 'ABC',
        'back': 'CBA',
        'down': 'ADG',
        'up': 'GDA',
        'down-right': 'AEI',
        'up-left': 'IEA',
        'down-left': 'CEG',
        'up-right': 'GEC',
      };
      for (final MapEntry<String, String> entry in byDirection.entries) {
        expect(containsWord(plain, entry.value), isTrue, reason: entry.key);
      }
      expect(byDirection, hasLength(wordDirections.length));
    });

    test('a word that is not there is not found', () {
      expect(containsWord(_grid, 'RESTA'), isFalse);
    });

    test('a word running off the edge does not wrap or truncate', () {
      expect(containsWord(_grid, 'SUMAXC'), isFalse);
      expect(containsWord(<String>['AB', 'CD'], 'ABC'), isFalse);
    });

    test('an empty word is not found', () {
      expect(containsWord(_grid, ''), isFalse);
    });
  });

  group('a claim is a straight line', () {
    test('a traced word is claimed', () {
      final WordSearchProgress after =
          WordSearchProgress(puzzle: _puzzle()).claim(_line(0, 0, 0, 1, 4));
      expect(after.found, contains('SUMA'));
    });

    test('traced backwards is the same word, because which end a player '
        'started from is not part of the puzzle', () {
      final WordSearchProgress after =
          WordSearchProgress(puzzle: _puzzle()).claim(_line(0, 3, 0, -1, 4));
      expect(after.found, contains('SUMA'));
    });

    test('a bent trace claims nothing', () {
      final WordSearchProgress after = WordSearchProgress(puzzle: _puzzle()).claim(
        <Cell>[
          const Cell(row: 0, col: 0),
          const Cell(row: 0, col: 1),
          const Cell(row: 1, col: 1),
        ],
      );
      expect(after.found, isEmpty);
    });

    test('a trace with a gap claims nothing', () {
      final WordSearchProgress after = WordSearchProgress(puzzle: _puzzle()).claim(
        <Cell>[const Cell(row: 0, col: 0), const Cell(row: 0, col: 2)],
      );
      expect(after.found, isEmpty);
    });

    test('a single cell claims nothing', () {
      expect(
        WordSearchProgress(puzzle: _puzzle())
            .claim(<Cell>[const Cell(row: 0, col: 0)]).found,
        isEmpty,
      );
    });

    test('a line of letters that is not a word claims nothing', () {
      final WordSearchProgress after =
          WordSearchProgress(puzzle: _puzzle()).claim(_line(2, 0, 0, 1, 3));
      expect(after.found, isEmpty);
    });

    test('a trace off the grid claims nothing', () {
      expect(
        WordSearchProgress(puzzle: _puzzle()).claim(_line(0, 3, 0, 1, 4)).found,
        isEmpty,
      );
    });

    test('claiming a found word again changes nothing', () {
      final WordSearchProgress once =
          WordSearchProgress(puzzle: _puzzle()).claim(_line(0, 0, 0, 1, 4));
      final WordSearchProgress twice = once.claim(_line(0, 0, 0, 1, 4));
      expect(twice.found, once.found);
      expect(twice.found, hasLength(1));
    });
  });

  group('finished means every word', () {
    test('the last word solves it', () {
      WordSearchProgress progress = WordSearchProgress(puzzle: _puzzle());
      expect(progress.isSolved, isFalse);

      progress = progress.claim(_line(0, 0, 0, 1, 4));
      expect(progress.isSolved, isFalse, reason: 'CERO is still missing');

      progress = progress.claim(_line(1, 0, 1, 0, 4));
      expect(progress.isSolved, isTrue);
    });

    test('a puzzle of one word is solved by that word', () {
      final WordSearchProgress after =
          WordSearchProgress(puzzle: _puzzle(words: <String>['SUMA']))
              .claim(_line(0, 0, 0, 1, 4));
      expect(after.isSolved, isTrue);
    });
  });
}
