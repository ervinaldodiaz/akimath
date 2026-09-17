import 'package:flutter_test/flutter_test.dart';

import 'source_tree.dart';

/// **Boards arrive in the pack; the device never makes one.**
///
/// `CLAUDE.md`: *never generate puzzles on demand; they go in batches.* The
/// reason is not tidiness. `checkUniqueSolution` is a search, it runs where the
/// pack is built, and a phone that had to prove a board unique before drawing it
/// would spend seconds and a slice of battery learning what the builder already
/// knew — while the player waits at a card that will not open.
///
/// The risk this guards is drift rather than a mistake anyone would make today:
/// the honest way to fix a bad board is to fix the content, and the tempting way
/// is a repair pass on the device.
void main() {
  /// Matched on **identifier boundaries**, not as substrings.
  ///
  /// The first draft used `contains` and its first run flagged
  /// `resolvePuzzleCell` — which contains "solve" and does nothing of the sort.
  /// A gate that cries wolf on a token-visual helper is a gate somebody
  /// deletes, so the letters either side have to be non-alphabetic.
  final List<RegExp> forbidden = <String>[
    'solve',
    'solving',
    'Solver',
    'backtrack',
    'permutation',
    'shuffle',
    'Random',
    'generateBoard',
    'uniqueSolution',
  ].map((String word) => RegExp('(?<![A-Za-z])$word(?![A-Za-z])')).toList();

  final SourceTree tree = SourceTree.readAppLib();
  final List<String> puzzleFiles = tree.sources.keys
      .where((String path) => path.startsWith('features/puzzle/'))
      .toList()
    ..sort();

  test('it walked a real tree', () {
    expect(
      puzzleFiles,
      isNotEmpty,
      reason: 'PROC-10: a mistyped prefix scans nothing and reports nothing, '
          'which looks exactly like a clean feature.',
    );
    // ignore: avoid_print
    print('  no puzzle generation · features/puzzle/ → '
        '${puzzleFiles.length} files');
  });

  test('nothing under features/puzzle/ solves or generates a board', () {
    final List<String> sightings = <String>[];
    for (final String path in puzzleFiles) {
      final List<String> lines = tree.sources[path]!.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        if (_isProse(line)) {
          continue;
        }
        for (final RegExp word in forbidden) {
          if (word.hasMatch(line)) {
            sightings.add('$path:${i + 1} mentions ${word.pattern}');
          }
        }
      }
    }

    expect(sightings, isEmpty,
        reason: 'a board must arrive already solved and already unique');
  });

  test('it sees a violation that is there, which every assertion above would '
      'pass without', () {
    const String probe = 'int solve(List<int> cells) => cells.first;';
    expect(
      forbidden.where((RegExp r) => r.hasMatch(probe)).toList(),
      isNotEmpty,
      reason: 'the scan cannot see a solver it was pointed at',
    );

    const String innocent = 'final v = resolvePuzzleCell(kind);';
    expect(
      forbidden.where((RegExp r) => r.hasMatch(innocent)).toList(),
      isEmpty,
      reason: 'resolvePuzzleCell is not a solver',
    );
  });
}

/// Whether [line] is prose rather than code.
///
/// **Prose is allowed to name the thing it forbids, and this file is the
/// proof**: every word on the forbidden list appears in the explanations above
/// at least as often as it would in a solver. A scan that read comments would
/// report its own reasoning, and a gate that cries wolf is a gate somebody
/// deletes.
bool _isProse(String line) =>
    line.trimLeft().startsWith('//') || line.trimLeft().startsWith('///');
