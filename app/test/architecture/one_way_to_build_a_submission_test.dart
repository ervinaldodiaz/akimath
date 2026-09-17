import 'package:flutter_test/flutter_test.dart';

import 'literal_scan.dart';
import 'source_tree.dart';

/// There is one place that turns a journalled answer into a wire submission.
///
/// **`JournalledAttempt.toSubmission` is that place, and this is what makes it
/// so.** It is the same shape as the server's `one-way-to-log.test.ts`: name
/// the files allowed to say the thing, and report what was actually found
/// rather than assert an absence.
///
/// It exists because the mapping was written twice. `toSubmission` had **zero
/// production callers** while `AttemptSync.flush` built the identical object
/// inline in its batch comprehension, and the consequence was not the schema
/// edit that looks like one site and is two. It was that
/// `attempt_journal_test.dart`'s *"the answer never travels online"* assertion
/// — an `ARCHITECTURE.md` §4 system invariant — read a method the app never
/// called. Measured before the fix: inverting `toSubmission` turned exactly one
/// named case red and left all twenty cases covering `flush` green, so the
/// shipping path was demonstrably indifferent to the method its test read.
///
/// Delegation alone would not hold that: nothing stops the next author
/// re-inlining the construction, and the gate the invariant needs is one that
/// goes red when they do.
void main() {
  const String theOneMapping = 'features/sync/policy/attempt_journal.dart';

  List<LiteralHit> scan(Map<String, String> sources) => findLiterals(
        sources: sources,
        roots: submissionBuildingRoots,
        patterns: submissionConstructionPatterns,
      );

  group('the scan', () {
    test('reports a submission built outside the mapping', () {
      final List<LiteralHit> hits = scan(<String, String>{
        'features/sync/attempt_sync.dart': '''
attempts: <AttemptSubmission>[
  for (final JournalledAttempt held in sending)
    AttemptSubmission.forPackItem(ref: PackRef(packId: held.packId)),
],
''',
      });

      expect(hits, hasLength(1));
      expect(hits.single.line, 3);
      expect(
        hits.single.message,
        allOf(contains('attempt_sync.dart'), contains('AttemptSubmission.forPackItem(')),
      );
    });

    test('and a generative constructor made public again', () {
      final List<LiteralHit> hits =
          scan(<String, String>{theOneMapping: '  AttemptSubmission(packRef: r);\n'});

      expect(hits.single.text, 'AttemptSubmission(');
    });

    test('naming the type is not building one, or the whole seam would report',
        () {
      expect(
        scan(<String, String>{
          'features/sync/attempt_sync.dart': '''
final List<AttemptSubmission> batch = <AttemptSubmission>[];
Future<SyncResult> Function({required List<AttemptSubmission> attempts})? submit;
''',
        }),
        isEmpty,
      );
    });

    test('and neither is a longer identifier that starts with the name', () {
      expect(
        scan(<String, String>{
          'features/sync/attempt_sync.dart':
              '  final AttemptSubmissionSpy spy = AttemptSubmissionSpy();\n',
        }),
        isEmpty,
      );
    });

    test('a mention in a comment is not a violation', () {
      expect(
        scan(<String, String>{
          'features/sync/attempt_sync.dart':
              '  // The journal owns it: held.toSubmission() builds the AttemptSubmission(…).\n',
        }),
        isEmpty,
      );
    });

    test('the class that declares it is outside the root', () {
      expect(
        scan(<String, String>{
          'api/sync.dart': '  AttemptSubmission.forPackItem({required PackRef ref});\n',
        }),
        isEmpty,
      );
    });
  });

  group('the gate over the real tree', () {
    final SourceTree tree = SourceTree.readAppLib();

    test('it reports how many files it scanned, and there are some', () {
      for (final String line in scanCoverageReport(
        libPaths: tree.sources.keys,
        roots: submissionBuildingRoots,
      )) {
        // ignore: avoid_print
        print('  one way to build a submission · $line');
      }
      expect(
        selectFilesIn(submissionBuildingRoots, tree.sources.keys),
        isNotEmpty,
        reason: 'the root matched nothing, so the gate proves nothing',
      );
    });

    test('exactly one file builds one, and it is the journal\'s own mapping', () {
      final List<LiteralHit> hits = findLiterals(
        sources: tree.sources,
        roots: submissionBuildingRoots,
        patterns: submissionConstructionPatterns,
      );
      final Set<String> builders =
          hits.map((LiteralHit hit) => hit.file).toSet();

      // ignore: avoid_print
      print('  one way to build a submission · ${hits.length} construction(s) '
          'in ${builders.length} file(s)');
      expect(
        builders,
        <String>{theOneMapping},
        reason: 'the mapping the frozen schema owns is written in '
            '${builders.join(', ')}; a schema change would have to find them all, '
            'and the test that pins "the answer never travels" reads only one',
      );
    });
  });
}
