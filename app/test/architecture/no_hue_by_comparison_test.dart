import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'literal_scan.dart';
import 'source_tree.dart';

/// A colour must never be chosen by comparing two numbers.
///
/// The shape this forbids is `pct >= 90 ? green : pink` written inline in a
/// widget. It scatters the thresholds that give a hue its meaning across every
/// screen that draws one, so changing what "mastered" means becomes a search
/// rather than an edit — and it is how a state ends up communicated by hue
/// alone, which BRD-1 forbids for a reader who cannot separate the two.
///
/// The alternative is a named level: `BaselineMeter(fill: MasteryLevel)`, with
/// the adapter resolving the level to a colour in one place.
void main() {
  group('the pattern', () {
    test('catches a threshold ternary picking a brand colour', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': 'final c = pct >= 90 ? BrandColors.green : BrandColors.pink;\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ),
        isNotEmpty,
      );
    });

    test('catches it across a line break', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': 'final c = score > threshold\n'
                '    ? BrandColorRole.success.color\n'
                '    : BrandColorRole.error.color;\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ),
        isNotEmpty,
      );
    });

    test('allows a colour resolved from an enum, which is the remedy itself',
        () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': 'final c = switch (level) {\n'
                '  MasteryLevel.mastered => BrandColors.green,\n'
                '  MasteryLevel.learning => BrandColors.yellow,\n'
                '};\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ),
        isEmpty,
      );
    });

    test('allows a null check or an enum comparison picking a colour', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': 'final c = verdict == null\n'
                '    ? BrandColorRole.focus.color\n'
                '    : BrandColorRole.error.color;\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ),
        isEmpty,
      );
    });

    test('allows a generic type argument followed by a colour', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': 'const List<Color> palette = <Color>[BrandColors.ink];\n'
                'final Map<String, Color> byName = <String, Color>{\n'
                '  "ink": BrandColors.ink,\n'
                '};\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ),
        isEmpty,
      );
    });

    test('allows a comparison that picks something other than a colour', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': 'final w = pct >= 90 ? 4.0 : 2.0;\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ),
        isEmpty,
      );
    });

    test('a commented-out threshold ternary is not a violation', () {
      expect(
        findLiterals(
          sources: <String, String>{
            'a.dart': '// final c = pct >= 90 ? BrandColors.green : x;\n',
          },
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
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
        roots: <ScanRoot>[hueGateRoot],
      );
      for (final String line in report) {
        stdout.writeln('  no hue by comparison · $line');
      }

      expect(hueGateRoot.selectFiles(tree.sources.keys), isNotEmpty);
    });

    test('no widget decides a hue by comparison today', () {
      final SourceTree tree = SourceTree.readAppLib();

      expect(
        findLiterals(
          sources: tree.sources,
          roots: <ScanRoot>[hueGateRoot],
          patterns: hueByComparisonPatterns,
        ).map((LiteralHit hit) => hit.message),
        isEmpty,
        reason: 'A hue chosen by a threshold scatters the meaning of that hue '
            'across every screen that draws one. Take a named level instead.',
      );
    });
  });
}
