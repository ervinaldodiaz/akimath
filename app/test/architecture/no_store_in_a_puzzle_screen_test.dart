import 'package:flutter_test/flutter_test.dart';

import 'literal_scan.dart';
import 'source_tree.dart';

/// A puzzle screen reports; it does not record.
///
/// The two formats commit at different moments — a value on a board, a word
/// claimed — so a store in both screens would be one IO decision written twice
/// and free to diverge. The route owns the store and both screens call
/// `onPractised`.
///
/// `RoundScreen` does hold one, and is out of scope by design (see
/// `storeFreeScreenRoots`): there is one round screen, so the duplication this
/// prevents cannot arise there.
void main() {
  const String screenFile = 'features/puzzle/ui/puzzle_screen.dart';

  List<LiteralHit> scan(String source) => findLiterals(
        sources: <String, String>{screenFile: source},
        roots: storeFreeScreenRoots,
        patterns: storePatterns,
      );

  group('the scan', () {
    test('reports a store held by a puzzle screen', () {
      final List<LiteralHit> hits = scan('''
class PuzzleScreen extends StatefulWidget {
  final DayLogStore? dayLog;
}
''');

      expect(hits, hasLength(1));
      expect(hits.single.line, 2);
      expect(
        hits.single.message,
        allOf(contains(screenFile), contains(':2'), contains('DayLogStore')),
      );
    });

    test('a callback that reports practice is not a store', () {
      expect(scan('  final VoidCallback? onPractised;\n'), isEmpty);
    });

    test('the name is matched whole, so a test double is not the thing', () {
      expect(scan('  final DayLogStoreSpy spy;\n'), isEmpty);
      expect(scan('  final FakeDayLogStore store;\n'), isEmpty);
    });

    test('a mention in a comment is not a violation', () {
      expect(
        scan('  // The route owns the DayLogStore, not this screen.\n'),
        isEmpty,
      );
    });

    test('the round screen is outside the root', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'features/round/ui/round_screen.dart': '  final DayLogStore? dayLog;\n',
          },
          roots: storeFreeScreenRoots,
          patterns: storePatterns,
        ),
        isEmpty,
      );
    });
  });

  group('the gate over the real tree', () {
    final SourceTree tree = SourceTree.readAppLib();

    test('it reports how many files it scanned, and there are some', () {
      final List<String> report = scanCoverageReport(
        libPaths: tree.sources.keys,
        roots: storeFreeScreenRoots,
      );
      for (final String line in report) {
        // ignore: avoid_print
        print('  no store in a puzzle screen · $line');
      }
      expect(
        selectFilesIn(storeFreeScreenRoots, tree.sources.keys),
        isNotEmpty,
        reason: 'the root matched nothing, so the gate proves nothing',
      );
    });

    test('no puzzle screen holds a store today', () {
      final List<LiteralHit> hits = findLiterals(
        sources: tree.sources,
        roots: storeFreeScreenRoots,
        patterns: storePatterns,
      );

      expect(hits.map((LiteralHit h) => h.message), isEmpty);
    });
  });
}
