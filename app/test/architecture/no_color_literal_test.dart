import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'literal_scan.dart';
import 'source_tree.dart';

/// BRD-2b as a red build: no colour literal outside `app/lib/design/tokens/`.
///
/// The rule was a `grep` a reviewer had to remember to run. It is a hard
/// problem in one direction only — `Colors.` is a **substring of
/// `BrandColors.`**, which is the correct, mandated way every widget in this
/// repository names a hue, so a naive scan is red on day one against ~94 lines
/// of correct code. A colour gate's difficulty is its false positives, not its
/// recall, and that is what most of this file asserts.
///
/// The scan is proven against synthetic sources, the way `pure_boundary_test`
/// proves its closure: a file that violates the rule is a map entry here, never
/// something written under `app/lib/`.
void main() {
  const String widgetFile = 'design/widgets/candy_surface.dart';

  List<LiteralHit> scan(String source) => findLiterals(
        sources: <String, String>{widgetFile: source},
        roots: const <ScanRoot>[colorGateRoot],
        patterns: colorLiteralPatterns,
      );

  group('the scan', () {
    test('reports a colour constructor with its file, line and text', () {
      final List<LiteralHit> hits = scan('''
class Key extends StatelessWidget {
  static const Color fill = Color(0xFFEAE6F0);
}
''');

      expect(hits, hasLength(1));
      expect(hits.single.line, 2);
      expect(
        hits.single.message,
        allOf(contains(widgetFile), contains(':2'), contains('Color(0xFFEAE6F0')),
      );
    });

    test('reports the two component constructors as well', () {
      expect(
        scan('''
const Color a = Color.fromARGB(255, 1, 2, 3);
const Color b = Color.fromRGBO(1, 2, 3, 1);
''').map((LiteralHit hit) => hit.line),
        <int>[1, 2],
      );
    });

    test('reports a constructor split across lines, citing where it starts',
        () {
      expect(
        scan('''
const Color fill = Color(
  0xFFEAE6F0,
);
''').single.line,
        1,
      );
    });

    test('BrandColors is not Material\'s palette, and the gate turns on that',
        () {
      expect(
        scan('''
Container(color: BrandColors.ink, child: Text('x', style: BrandText.body()));
'''),
        isEmpty,
      );
    });

    test('an identifier merely ending in Colors is not the palette either', () {
      expect(scan('final Color c = LegacyColors.ink;\n'), isEmpty);
    });

    test('a brand hex printed as a label is not a colour literal', () {
      expect(
        scan("const String label = 'CUERPO #F7DFB6';\n"),
        isEmpty,
      );
    });

    test('a commented-out colour literal is not a violation', () {
      expect(scan('// was: Color(0xFFEAE6F0)\n'), isEmpty);
      expect(scan('/* Color(0xFFEAE6F0) */\n'), isEmpty);
    });

    test('Colors.transparent is matched by the pattern and then permitted', () {
      final List<LiteralHit> raw =
          scan('const Color none = Colors.transparent;\n');

      expect(raw.single.text, permittedColorLiteral);
      expect(withoutPermitted(raw), isEmpty);
    });

    test('every other Material colour stays a violation', () {
      final List<LiteralHit> raw = scan('const Color c = Colors.red;\n');

      expect(withoutPermitted(raw).single.text, 'Colors.red');
    });
  });

  group('the root', () {
    test('governs all of lib except the tokens themselves', () {
      expect(colorGateRoot.contains('design/widgets/speech_bubble.dart'), isTrue);
      expect(colorGateRoot.contains('features/splash/splash_screen.dart'), isTrue);
      expect(colorGateRoot.contains('main.dart'), isTrue);
      expect(colorGateRoot.contains('design/tokens/brand_colors.dart'), isFalse);
    });

    test('the palette file itself is where the literals are allowed to live',
        () {
      expect(
        findLiterals(
          sources: const <String, String>{
            'design/tokens/brand_colors.dart':
                'static const Color ink = Color(0xFF1C1A2E);\n',
          },
          roots: const <ScanRoot>[colorGateRoot],
          patterns: colorLiteralPatterns,
        ),
        isEmpty,
      );
    });
  });

  group('the gate over the real tree', () {
    test('it reports what it scanned, and scanning nothing is a failure', () {
      final SourceTree tree = SourceTree.readAppLib();

      final List<String> report = scanCoverageReport(
        libPaths: tree.sources.keys,
        roots: const <ScanRoot>[colorGateRoot],
      );
      for (final String line in report) {
        stdout.writeln('  no colour literal · $line');
      }

      expect(
        selectFilesIn(const <ScanRoot>[colorGateRoot], tree.sources.keys),
        isNotEmpty,
        reason: 'The root resolved to no file. A path typo makes this gate '
            'permanently green, which is the one failure mode it cannot have.',
      );
    });

    test('the palette arm matches Material and nothing else, before the '
        'carve-out is subtracted', () {
      final List<LiteralHit> hits = findLiterals(
        sources: SourceTree.readAppLib().sources,
        roots: const <ScanRoot>[colorGateRoot],
        patterns: <LiteralPattern>[materialPalette],
      );

      expect(
        hits.map((LiteralHit hit) => hit.file).toSet(),
        <String>{'design/theme.dart'},
      );
      expect(hits, hasLength(4));
      expect(
        hits.map((LiteralHit hit) => hit.text).toSet(),
        <String>{permittedColorLiteral},
      );
    });

    test('no colour literal lives outside design/tokens/ today', () {
      final List<LiteralHit> violations = withoutPermitted(
        findLiterals(
          sources: SourceTree.readAppLib().sources,
          roots: const <ScanRoot>[colorGateRoot],
          patterns: colorLiteralPatterns,
        ),
      );

      expect(
        violations.map((LiteralHit hit) => hit.message),
        isEmpty,
        reason: 'Every hue comes from BrandColors and every state from '
            'BrandColorRole (BRD-2b).',
      );
    });
  });
}
