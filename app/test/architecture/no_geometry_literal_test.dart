import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'literal_scan.dart';
import 'source_tree.dart';

/// No widget surface writes its own hard-shadow offset.
///
/// The offsets are `BrandShape`'s and a screen asks for one by role.
/// `Offset(4, 6)` was the most common shadow in the app and was written as a
/// literal, so the scale could not be trusted as the single source of the
/// geometry.
///
/// **Scope is deliberately narrow, and the narrowness is the decision.**
/// `app/lib/design/brand/` is out: 95 offsets in `aki_spec.dart` and one
/// proportional expression in `app_icon.dart` are the artwork layer, where
/// geometry *is* the content (design D9). Radii and border widths are not
/// scanned at all — a bare `24` is not greppable without parsing, and a gate
/// that pretended to cover them would be a false claim.
void main() {
  const String widgetFile = 'design/widgets/speech_bubble.dart';

  List<LiteralHit> scan(String source) => findLiterals(
        sources: <String, String>{widgetFile: source},
        roots: geometryGateRoots,
        patterns: geometryLiteralPatterns,
      );

  group('the scan', () {
    test('reports an offset literal with its file, line and text', () {
      final List<LiteralHit> hits = scan('''
const BoxShadow shadow = BoxShadow(
  offset: Offset(4, 6),
);
''');

      expect(hits, hasLength(1));
      expect(hits.single.line, 2);
      expect(
        hits.single.message,
        allOf(contains(widgetFile), contains(':2'), contains('Offset(')),
      );
    });

    test('a token read is what the gate is asking for', () {
      expect(scan('offset: BrandShape.shadowButton,\n'), isEmpty);
    });

    test('Offset.zero is not a literal offset', () {
      expect(scan('const Offset origin = Offset.zero;\n'), isEmpty);
    });

    test('an identifier merely ending in Offset is not a violation', () {
      expect(scan('final Offset o = tailOffset(size);\n'), isEmpty);
    });

    test('a commented-out offset is not a violation', () {
      expect(scan('// offset: Offset(4, 6),\n'), isEmpty);
    });
  });

  group('the roots', () {
    test('govern the widget surfaces and the screens', () {
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/widgets/speech_bubble.dart',
          'features/splash/splash_screen.dart',
        ]),
        hasLength(2),
      );
    });

    test('govern the math adapter too, which composes tokens rather than art',
        () {
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/math/math_view.dart',
        ]),
        hasLength(1),
      );
    });

    test('exclude the figurate layout by file, and nothing else beside it', () {
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/math/spec/figurate_layout.dart',
        ]),
        isEmpty,
        reason: 'it returns positions it computed, not a shadow offset',
      );
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/math/spec/math_node.dart',
          'design/math/spec/fraction_metrics.dart',
          'design/math/spec/es_mx_number.dart',
        ]),
        hasLength(3),
        reason: 'the rest of the compositor spec stays governed',
      );
    });

    test('follow the cage painter out of design/painting/ into design/puzzle/',
        () {
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/puzzle/cage_edge_painter.dart',
        ]),
        hasLength(1),
      );
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/puzzle/spec/board_geometry.dart',
          'design/puzzle/spec/letter_grid_geometry.dart',
        ]),
        isEmpty,
        reason: 'they return positions they computed, not a shadow offset',
      );
    });

    test('leave the artwork layer alone', () {
      expect(
        selectFilesIn(geometryGateRoots, const <String>[
          'design/brand/spec/aki_spec.dart',
          'design/brand/app_icon.dart',
        ]),
        isEmpty,
        reason: 'aki_spec.dart holds 95 of these and every one is correct',
      );
    });
  });

  group('the gate over the real tree', () {
    test('it reports what it scanned, and scanning nothing is a failure', () {
      final SourceTree tree = SourceTree.readAppLib();

      final List<String> report = scanCoverageReport(
        libPaths: tree.sources.keys,
        roots: geometryGateRoots,
      );
      for (final String line in report) {
        stdout.writeln('  no geometry literal · $line');
      }

      for (final ScanRoot root in geometryGateRoots) {
        expect(
          root.selectFiles(tree.sources.keys),
          isNotEmpty,
          reason: '${root.label} resolved to no file. A path typo makes this '
              'gate permanently green, which is the one failure mode it '
              'cannot have.',
        );
      }
    });

    test('no widget surface writes an offset literal today', () {
      expect(
        findLiterals(
          sources: SourceTree.readAppLib().sources,
          roots: geometryGateRoots,
          patterns: geometryLiteralPatterns,
        ).map((LiteralHit hit) => hit.message),
        isEmpty,
        reason: 'Hard-shadow offsets come from BrandShape (BRD-2c).',
      );
    });
  });
}
