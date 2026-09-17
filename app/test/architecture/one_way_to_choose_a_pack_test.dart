import 'package:flutter_test/flutter_test.dart';

import 'literal_scan.dart';
import 'source_tree.dart';

/// There is one place that decides which pack is in play and whether it may be
/// played.
///
/// **`features/sync/policy/pack_in_play.dart` is that place, and this is what
/// makes it so.** Same shape as `one_way_to_build_a_submission_test.dart` and
/// the server's `one-way-to-log.test.ts`: name the file allowed to say the
/// thing, and report what was found rather than assert an absence.
///
/// It exists because the decision had two owners that had already disagreed.
/// `HomeRoute` resolved *the issued pack, or else the bundled one* and asked
/// `isExpiredAt`; `MapRoute` resolved the same pair and asked nothing — the
/// word appeared twice in one file and not once in the other. So the day
/// `assets/packs/starter.json` lapses, with no server and no account in the
/// story, Inicio says the challenges expired and Mapa draws a full map of
/// topics with a live `Practicar 5 retos` on every one of them. One app, two
/// answers, and the one that lets you play is the wrong one.
///
/// **What this gate does not catch, said plainly so nobody retires the question
/// by reading the name (CMT-3).** It fires on a second screen *asking* about
/// the window, not on a third one forgetting to. A new route that writes
/// `_issued ?? bundled` and never mentions `isExpiredAt` stays green here, and
/// the bundled pack is one `PackReader.load()` away from anybody. The
/// `readIssuedPack` half narrows that only as far as a text scan can: it keeps
/// *the parse* in one place, and it does not make every server pack pass the
/// window question, because `packFrom` and `packInPlay` are independent exports
/// of the module. What covers the forgetting is each route's own case — the
/// map's `a lapsed pack draws no map` and the home's `an expired pack is
/// refused` — and the rest is a reviewer's read.
void main() {
  const String theOneOwner = 'features/sync/policy/pack_in_play.dart';

  List<LiteralHit> scan(Map<String, String> sources) => findLiterals(
        sources: sources,
        roots: packChoiceRoots,
        patterns: packChoicePatterns,
      );

  group('the scan', () {
    test('reports a screen asking about the window itself', () {
      final List<LiteralHit> hits = scan(<String, String>{
        'features/map/ui/map_route.dart':
            '    if (pack.isExpiredAt(widget.now())) {\n',
      });

      expect(hits, hasLength(1));
      expect(hits.single.line, 1);
      expect(
        hits.single.message,
        allOf(contains('map_route.dart'), contains('isExpiredAt(')),
      );
    });

    test('and a second reader of an issued pack, the module being the one door',
        () {
      final List<LiteralHit> hits = scan(<String, String>{
        'features/home/ui/home_route.dart':
            '      final Pack pack = readIssuedPack(body, packId: id);\n',
      });

      expect(hits.single.text, 'readIssuedPack(');
    });

    test('naming either in prose is not deciding anything, and this file is '
        'the proof', () {
      expect(
        scan(<String, String>{
          'features/map/ui/map_route.dart': '''
// `packInPlay` asks isExpiredAt( so this file does not, and readIssuedPack(
// is called through `packFrom`.
''',
        }),
        isEmpty,
      );
    });

    test('and neither is a longer identifier that starts with the name', () {
      expect(
        scan(<String, String>{
          'features/home/ui/home_route.dart':
              '  final bool gone = pack.isExpiredAtLaunch();\n'
                  '  readIssuedPackTwice();\n',
        }),
        isEmpty,
      );
    });

    test('the two files that declare them are outside the root', () {
      expect(
        scan(<String, String>{
          'content/model/pack.dart':
              '  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);\n',
          'content/model/issued_pack.dart':
              'Pack readIssuedPack(Map<String, dynamic> json) {\n',
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
        roots: packChoiceRoots,
      )) {
        // ignore: avoid_print
        print('  one way to choose a pack · $line');
      }
      expect(
        selectFilesIn(packChoiceRoots, tree.sources.keys),
        isNotEmpty,
        reason: 'the root matched nothing, so the gate proves nothing',
      );
    });

    test('exactly one file decides, and it is the pure policy', () {
      final List<LiteralHit> hits = findLiterals(
        sources: tree.sources,
        roots: packChoiceRoots,
        patterns: packChoicePatterns,
      );
      final Set<String> deciders =
          hits.map((LiteralHit hit) => hit.file).toSet();

      // ignore: avoid_print
      print('  one way to choose a pack · ${hits.length} decision(s) '
          'in ${deciders.length} file(s)');
      expect(
        deciders,
        <String>{theOneOwner},
        reason: 'which pack is in play is decided in '
            '${deciders.join(', ')}; two roots deciding it separately is how '
            'Mapa came to offer a practice run on a pack Inicio was refusing',
      );
    });
  });
}
