import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'import_graph.dart';
import 'source_tree.dart';

/// A `policy/` file that exists only as a map entry. No `features/*/policy/`
/// directory is created by this test — design D-1.
const String _policyFile = 'features/round/policy/answer_draft.dart';

/// The executable form of the import ceiling in the implementation plan §2.2.
///
/// The resolver under test is pure, so a scenario that describes a repository
/// which would not compile — a `policy/` file reaching Flutter through the
/// token barrel, two feature barrels importing each other — is a map handed to
/// a function here, never a file written under `app/lib/`.
void main() {
  group('directive extraction', () {
    test('reads the targets of both import and export', () {
      const String source = '''
import 'package:meta/meta.dart';
export 'brand_colors.dart';
export 'brand_typography.dart';
''';

      expect(
        readDirectives(source).map((SourceDirective d) => d.uri),
        <String>[
          'package:meta/meta.dart',
          'brand_colors.dart',
          'brand_typography.dart',
        ],
      );
    });

    test('records the kind and the line of each directive', () {
      const String source = '''
library;

import 'dart:math';
export 'answer_draft.dart';
part 'answer_draft.g.dart';
''';

      expect(
        readDirectives(source).map((SourceDirective d) => d.toString()),
        <String>[
          '3: import dart:math',
          '4: export answer_draft.dart',
          '5: part answer_draft.g.dart',
        ],
      );
    });

    test('ignores an import commented out with a line comment', () {
      const String source = '''
// import 'package:flutter/material.dart';
import 'dart:math';
''';

      expect(
        readDirectives(source).map((SourceDirective d) => d.uri),
        <String>['dart:math'],
      );
    });

    test('ignores an import commented out with a block comment', () {
      const String source = '''
/* the old shape:
import 'package:flutter/material.dart';
*/
import 'dart:math';
''';

      expect(
        readDirectives(source).map((SourceDirective d) => d.uri),
        <String>['dart:math'],
      );
    });

    test('ignores a trailing comment naming a forbidden package', () {
      const String source = '''
import 'dart:math'; // never package:flutter/material.dart
''';

      expect(
        readDirectives(source).map((SourceDirective d) => d.uri),
        <String>['dart:math'],
      );
    });
  });

  group('canonical lib paths', () {
    test('the relative and the package spelling of the barrel are one key', () {
      const String barrel = 'design/tokens/tokens.dart';

      expect(
        canonicalLibPath(
          '../../../design/tokens/tokens.dart',
          fromLibPath: 'features/round/policy/answer_draft.dart',
        ),
        barrel,
      );
      expect(
        canonicalLibPath(
          'package:akimath_app/design/tokens/tokens.dart',
          fromLibPath: 'features/round/policy/answer_draft.dart',
        ),
        barrel,
      );
    });

    test('a sibling resolves against the importing file, not against lib', () {
      expect(
        canonicalLibPath(
          'brand_typography.dart',
          fromLibPath: 'design/tokens/tokens.dart',
        ),
        'design/tokens/brand_typography.dart',
      );
    });

    test('a URI outside the repository has no lib path — it is a leaf', () {
      expect(
        canonicalLibPath('dart:ui', fromLibPath: 'design/brand/spec/x.dart'),
        isNull,
      );
      expect(
        canonicalLibPath(
          'package:flutter/painting.dart',
          fromLibPath: 'design/brand/spec/x.dart',
        ),
        isNull,
      );
    });
  });

  group('leaf verdicts', () {
    test('plan §2.2 allows dart:ui, dart:math, dart:core and package:meta', () {
      for (final String uri in <String>[
        'dart:ui',
        'dart:math',
        'dart:core',
        'package:meta/meta.dart',
      ]) {
        expect(leafVerdict(uri), LeafVerdict.allowed, reason: uri);
      }
    });

    test('Flutter, dart:io and any other package are forbidden', () {
      for (final String uri in <String>[
        'package:flutter/material.dart',
        'package:flutter/painting.dart',
        'dart:io',
        'package:collection/collection.dart',
      ]) {
        expect(leafVerdict(uri), LeafVerdict.forbidden, reason: uri);
      }
    });

    test('dart:async is forbidden, though dart:core already gives Future and '
        'Stream', () {
      expect(
        leafVerdict('dart:async'),
        LeafVerdict.forbidden,
        reason: 'design D-3: plan §2.2 lists it, so it stays on the list, but '
            'the entry keeps nothing out — and the body scan that would is a '
            'stated non-goal',
      );
    });

    test('an unlisted dart: library fails closed', () {
      expect(leafVerdict('dart:convert'), LeafVerdict.forbidden);
    });
  });

  group('pure roots', () {
    test('a file is inside the root that holds its directory', () {
      expect(
        PureRoot.designSpec.containsFile('design/brand/spec/aki_spec.dart'),
        isTrue,
      );
      expect(
        PureRoot.featurePolicy
            .containsFile('features/round/policy/answer_draft.dart'),
        isTrue,
      );
      expect(
        PureRoot.contentModel.containsFile('content/model/item.dart'),
        isTrue,
      );
    });

    test('a file beside a root is not inside it', () {
      expect(
        PureRoot.designSpec.containsFile('design/brand/aki.dart'),
        isFalse,
      );
      expect(
        PureRoot.featurePolicy
            .containsFile('features/round/ui/answer_card.dart'),
        isFalse,
      );
      expect(
        PureRoot.contentModel.containsFile('content/data/pack_reader.dart'),
        isFalse,
      );
    });
  });

  group('the source tree adapter', () {
    test('reads the real app/lib into lib-relative keys', () {
      final SourceTree tree = SourceTree.readAppLib();

      expect(tree.sources.keys, contains('design/brand/spec/aki_spec.dart'));
      expect(
        tree.sources.keys,
        contains('design/tokens/brand_typography.dart'),
      );
      expect(
        tree.sources['design/tokens/tokens.dart'],
        contains("export 'brand_typography.dart';"),
      );
    });

    test('resolves each pure root it is asked about against the real tree', () {
      final SourceTree tree = SourceTree.readAppLib();

      expect(tree.presentRoots, contains(PureRoot.designSpec));
      expect(tree.presentRoots, contains(PureRoot.featurePolicy));
      expect(tree.presentRoots, contains(PureRoot.contentModel));
    });

    test('refuses a lib root that does not resolve, or the gate is vacuous',
        () {
      expect(
        () => SourceTree.readFrom(Directory('lib/nowhere')),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            allOf(contains('nowhere'), contains(Directory.current.path)),
          ),
        ),
      );
    });
  });

  group('the transitive closure', () {
    /// The real token barrel plus one `policy/` file that does not exist on
    /// disk and must not be written there (design D-1): the scenario describes
    /// a repository that would not compile.
    Map<String, String> graphWithPolicyImportingTheBarrel() {
      return <String, String>{
        ...SourceTree.readAppLib().sources,
        _policyFile: "import '../../../design/tokens/tokens.dart';\n",
      };
    }

    test('a policy file importing the barrel is caught through its exports',
        () {
      final List<BoundaryViolation> violations = findBoundaryViolations(
        sources: graphWithPolicyImportingTheBarrel(),
        pureFiles: <String>[_policyFile],
      );

      expect(violations, hasLength(1));
      expect(
        violations.single.message,
        allOf(
          contains(_policyFile),
          contains('design/tokens/tokens.dart'),
          contains('design/tokens/brand_typography.dart'),
          contains('package:flutter/painting.dart'),
        ),
      );
    });

    test('a walk that follows only import reports zero on the same graph', () {
      expect(
        findBoundaryViolations(
          sources: graphWithPolicyImportingTheBarrel(),
          pureFiles: <String>[_policyFile],
          follow: const <DirectiveKind>{DirectiveKind.import},
        ),
        isEmpty,
        reason: 'tokens.dart holds three exports and no import, so the edge to '
            'brand_typography.dart is invisible to an import-only walk at any '
            'depth — which is why the closure follows export and part',
      );
    });

    test('a walk that stops after one hop reports zero on the same graph', () {
      expect(
        findBoundaryViolations(
          sources: graphWithPolicyImportingTheBarrel(),
          pureFiles: <String>[_policyFile],
          maxHops: 1,
        ),
        isEmpty,
      );
    });

    test('a part file cannot smuggle a forbidden import past the closure', () {
      const String library = 'features/round/policy/round_policy.dart';
      const String part = 'features/round/policy/round_policy_extra.dart';

      final List<BoundaryViolation> violations = findBoundaryViolations(
        sources: const <String, String>{
          library: "part 'round_policy_extra.dart';\n",
          part: "import 'package:flutter/material.dart';\n",
        },
        pureFiles: const <String>[library],
      );

      expect(violations.single.forbiddenUri, 'package:flutter/material.dart');
    });

    test('a pure file reaching only allowed leaves yields nothing', () {
      final SourceTree tree = SourceTree.readAppLib();

      expect(
        findBoundaryViolations(
          sources: tree.sources,
          pureFiles: <String>['design/brand/spec/aki_spec.dart'],
        ),
        isEmpty,
      );
    });
  });

  group('feature barrel cycles', () {
    test('two features importing each other are reported with the cycle', () {
      final List<List<String>> cycles =
          findFeatureBarrelCycles(const <String, String>{
        'features/home/home.dart': "import '../shell/shell.dart';\n",
        'features/shell/shell.dart': "import '../home/home.dart';\n",
      });

      expect(cycles, hasLength(1));
      expect(cycles.single, <String>[
        'features/home/home.dart',
        'features/shell/shell.dart',
        'features/home/home.dart',
      ]);
    });

    test('a cycle closing through a non-barrel file is still reported, which '
        'is the plan\'s own trap', () {
      final List<List<String>> cycles =
          findFeatureBarrelCycles(const <String, String>{
        'features/shell/shell.dart': "export 'ui/router.dart';\n",
        'features/shell/ui/router.dart': "import '../../home/home.dart';\n",
        'features/home/home.dart': "import '../shell/shell.dart';\n",
      });

      expect(cycles, hasLength(1));
      expect(cycles.single, contains('features/shell/ui/router.dart'));
    });

    test('a one-way edge between barrels is not a cycle', () {
      expect(
        findFeatureBarrelCycles(const <String, String>{
          'features/onboarding/onboarding.dart':
              "import '../round/round.dart';\n",
          'features/round/round.dart': "export 'ui/answer_card.dart';\n",
          'features/round/ui/answer_card.dart': "import 'dart:ui';\n",
        }),
        isEmpty,
      );
    });

    test('the real tree holds no cycle', () {
      expect(findFeatureBarrelCycles(SourceTree.readAppLib().sources), isEmpty);
    });
  });

  group('the ambient scan', () {
    List<AmbientAccess> scan(String source) => findAmbientAccess(
          sources: <String, String>{_policyFile: source},
          pureFiles: const <String>[_policyFile],
        );

    test('a clock read is reported with its file and its line', () {
      final List<AmbientAccess> found = scan('''
int millisecondOfNow() {
  return DateTime.now().millisecond;
}
''');

      expect(found, hasLength(1));
      expect(found.single.line, 2);
      expect(
        found.single.message,
        allOf(contains(_policyFile), contains(':2'), contains('DateTime.now')),
      );
    });

    test('randomness is reported with its line', () {
      expect(scan('final int roll = Random(7).nextInt(6);\n').single.line, 1);
    });

    test('a platform read is reported with its line', () {
      expect(
        scan('\n\nfinal bool phone = Platform.isIOS;\n').single.line,
        3,
      );
    });

    test('a line number survives a preceding block comment', () {
      expect(
        scan('''
/* the old shape
   kept for one release */
final int roll = Random(7).nextInt(6);
''').single.line,
        3,
        reason: 'the strip blanks comment text in place; one that deleted '
            'lines would cite the wrong one, and nothing else would notice',
      );
    });

    test('a commented-out clock read is not a violation', () {
      expect(scan('// return DateTime.now();\n'), isEmpty);
    });

    test('a now parameter is the shape §2.2 wants, not a violation', () {
      expect(
        scan(
          'Duration sinceIssue(DateTime issuedAt, DateTime now) =>\n'
          '    now.difference(issuedAt);\n',
        ),
        isEmpty,
      );
    });

    test('an identifier merely ending in Random is not a violation', () {
      expect(scan('final int seed = SeededRandom(7).next();\n'), isEmpty);
    });
  });

  group('the gate over the real tree', () {
    test('it reports what it scanned, per root', () {
      final SourceTree tree = SourceTree.readAppLib();

      final List<String> report = rootCoverageReport(
        libPaths: tree.sources.keys,
        presentRoots: tree.presentRoots,
      );
      for (final String line in report) {
        stdout.writeln('  pure boundary · $line');
      }

      expect(report, hasLength(PureRoot.values.length));
      expect(
        tree.presentRoots,
        isNotEmpty,
        reason: 'Not one pure root resolved. Every root would report absent '
            'and the gate would pass while scanning nothing.',
      );
      for (final PureRoot root in PureRoot.values) {
        final bool present = tree.presentRoots.contains(root);
        final int scanned = root.selectFiles(tree.sources.keys).length;
        if (present) {
          expect(
            scanned,
            greaterThan(0),
            reason: '${root.label} exists on disk and contributed no file.',
          );
          expect(report, contains('${root.label} → $scanned files'));
        } else {
          expect(report, contains('${root.label} → absent'));
        }
      }
    });

    test('no file under a pure root reaches a forbidden URI today', () {
      final SourceTree tree = SourceTree.readAppLib();
      final List<String> scanned = <String>[
        for (final PureRoot root in PureRoot.values)
          ...root.selectFiles(tree.sources.keys),
      ];

      expect(scanned, isNotEmpty, reason: 'Nothing was scanned.');
      expect(
        findBoundaryViolations(sources: tree.sources, pureFiles: scanned)
            .map((BoundaryViolation violation) => violation.message),
        isEmpty,
      );
    });

    test('no file under a pure root reads ambient state today', () {
      final SourceTree tree = SourceTree.readAppLib();
      final List<String> scanned = <String>[
        for (final PureRoot root in PureRoot.values)
          ...root.selectFiles(tree.sources.keys),
      ];

      expect(scanned, isNotEmpty, reason: 'Nothing was scanned.');
      expect(
        findAmbientAccess(sources: tree.sources, pureFiles: scanned)
            .map((AmbientAccess access) => access.message),
        isEmpty,
      );
    });
  });

  group('comment stripping', () {
    test('keeps the line count so a finding can cite a line', () {
      const String source = '''
/* one
two
three */
const int x = 1;
''';

      final List<String> stripped = stripComments(source).split('\n');

      expect(stripped.length, source.split('\n').length);
      expect(stripped[0], isNot(contains('one')));
      expect(stripped[1], isNot(contains('two')));
      expect(stripped[3], 'const int x = 1;');
    });

    test('leaves code that is not a comment untouched', () {
      const String source = "const String url = 'a';";

      expect(stripComments(source), source);
    });
  });
}
