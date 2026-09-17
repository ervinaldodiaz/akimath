/// Pure scanning of source text for the literals the token scale replaces.
///
/// This module is handed a map of lib-relative path to source text and returns
/// findings. It opens no file: the filesystem walk that produces the map is
/// `source_tree.dart`, the adapter beside it (PURE-1, PURE-2). Keeping the
/// matching on this side is what lets a file that violates BRD-2b be a map
/// entry in a test rather than a literal written under `app/lib/`.
///
/// Comment stripping is borrowed from `import_graph.dart` rather than written
/// again. Every one of these gates' false-positive stories depends on that one
/// behaviour, and three copies of it would drift apart on exactly the thing
/// that must not drift (design D11).
///
/// **Two stated limits, so they are read as limits and not found as bugs.**
/// `stripComments` copies string literals through verbatim, so a Dart string
/// whose text happens to contain `Colors.` or `Offset(` reports; nothing in
/// `app/lib/` does today. And a text scan cannot see a colour assembled at
/// runtime from ints. The gate raises the floor; it does not replace the
/// reviewer.
library;

import 'package:meta/meta.dart';

import 'import_graph.dart' show stripComments;

/// A directory the gates scan, together with what it does not govern.
@immutable
final class ScanRoot {
  const ScanRoot({required this.prefix, this.excluding = const <String>[]});

  /// A lib-relative directory prefix. The empty prefix is all of `app/lib/`.
  final String prefix;

  /// Prefixes inside [prefix] that this root does not govern.
  final List<String> excluding;

  /// How the root is named in the gate's report.
  String get label {
    final String scope = prefix.isEmpty ? 'lib/' : prefix;
    return excluding.isEmpty ? scope : '$scope minus ${excluding.join(' and ')}';
  }

  /// Whether a lib-relative file path lies inside this root.
  bool contains(String libPath) =>
      libPath.startsWith(prefix) &&
      !excluding.any((String excluded) => libPath.startsWith(excluded));

  /// The files of [libPaths] this root governs, in a stable order.
  List<String> selectFiles(Iterable<String> libPaths) =>
      libPaths.where(contains).toList()..sort();
}

/// The files [roots] govern between them, deduplicated and in a stable order.
List<String> selectFilesIn(Iterable<ScanRoot> roots, Iterable<String> libPaths) {
  final Set<String> selected = <String>{
    for (final ScanRoot root in roots) ...root.selectFiles(libPaths),
  };
  return selected.toList()..sort();
}

/// One line per root, naming what the gate actually looked at.
///
/// The count is printed rather than inferred from a green run: a gate whose
/// root is one typo away from matching nothing passes forever, and that is the
/// failure mode `dart_code_linter` already demonstrates in this repository
/// (PROC-5 — a check that can only ever be green is not evidence).
List<String> scanCoverageReport({
  required Iterable<String> libPaths,
  required Iterable<ScanRoot> roots,
}) {
  return <String>[
    for (final ScanRoot root in roots)
      '${root.label} → ${root.selectFiles(libPaths).length} files',
  ];
}

/// One textual form a literal is written in, named as the gate reports it.
@immutable
final class LiteralPattern {
  LiteralPattern(this.label, String expression)
      : _expression = RegExp(expression);

  /// How the form is written in a failure message.
  final String label;

  final RegExp _expression;

  Iterable<RegExpMatch> matchesIn(String source) =>
      _expression.allMatches(source);
}

/// One literal found, with enough to name it in a failure.
@immutable
final class LiteralHit {
  const LiteralHit({
    required this.file,
    required this.line,
    required this.text,
  });

  final String file;
  final int line;

  /// The matched source, with internal whitespace collapsed so a construction
  /// broken across lines still reads as what it is.
  final String text;

  String get message => '$file:$line writes $text';

  @override
  String toString() => message;
}

/// Material's palette — the arm that has to be matched on a word boundary.
///
/// `Colors.` is a **substring of `BrandColors.`**, the mandated way every
/// widget here names a hue, so a substring match reports ~94 correct lines
/// across 12 files. The negative lookbehind is the difference between a gate
/// and a gate somebody had to disable (design D8).
final LiteralPattern materialPalette = LiteralPattern(
  'Colors.',
  r'(?<![A-Za-z0-9_$])Colors\s*\.\s*[A-Za-z_][A-Za-z0-9_]*',
);

/// Every way a colour is written literally in Dart.
///
/// Deliberately not `#RRGGBB`: the character sheet prints four brand hexes as
/// swatch labels and is correct code (design D8). Derived colours are out of
/// scope by construction — `withValues(alpha:)` takes a token and adjusts it,
/// which is what tokens are for.
final List<LiteralPattern> colorLiteralPatterns = <LiteralPattern>[
  LiteralPattern('Color(0x…)', r'(?<![A-Za-z0-9_$])Color\s*\(\s*0x[0-9A-Fa-f]+'),
  LiteralPattern(
    'Color.fromARGB(',
    r'(?<![A-Za-z0-9_$])Color\s*\.\s*fromARGB\s*\(',
  ),
  LiteralPattern(
    'Color.fromRGBO(',
    r'(?<![A-Za-z0-9_$])Color\s*\.\s*fromRGBO\s*\(',
  ),
  materialPalette,
];

/// The hard-shadow offsets a widget surface must take from `BrandShape`.
///
/// Radii and border widths are **not** scanned: a bare `24` is not greppable
/// without parsing, and a gate that pretended to cover them would be a false
/// claim in the rulebook. BRD-2c stays a reviewer's read on those two.
final List<LiteralPattern> geometryLiteralPatterns = <LiteralPattern>[
  LiteralPattern('Offset(', r'(?<![A-Za-z0-9_$])Offset\s*\('),
];

/// All of `app/lib/` except the tokens, which are where the literals live.
const ScanRoot colorGateRoot = ScanRoot(
  prefix: '',
  excluding: <String>['design/tokens/'],
);

/// The widget surfaces `BrandShape` governs.
///
/// `design/brand/` is out of scope: 95 offsets in `aki_spec.dart` and one
/// proportional expression in `app_icon.dart` are the artwork layer, where
/// geometry *is* the content (design D9).
///
/// `design/math/` **is** in scope, and the distinction is worth stating because
/// it looks like the artwork case and is not. The compositor composes tokens
/// the way `design/widgets/` does; its geometry comes from `FractionMetrics`
/// and an injected x-height, never from a number typed while reading a mock.
///
/// **`figurate_layout.dart` is the one file excluded, and the exclusion is a
/// file rather than its directory.** It is the artwork case that arrived inside
/// a spec root: it answers "where do the dots of a figurate number go" and
/// returns positions in a unit box, so the `Offset` it constructs holds two
/// numbers it just computed from a count — the same standing as the `Rect`
/// `FractionMetrics` returns, which this gate has never objected to. What the
/// gate is actually protecting is that a *shadow* offset comes from
/// `BrandShape`, and there is no shadow within reach of that file. Excluding
/// the directory instead would have taken `math_node.dart` and
/// `es_mx_number.dart` out with it for no reason.
///
/// `design/painting/` is in scope for the same reason: it is where a border
/// moves when it stops being a `BoxDecoration`, and a painted outline is no
/// less governed by `BrandShape` than a decorated one.
///
/// **`design/puzzle/` joined it when the cage painter moved there**, and its
/// `spec/` half is the one exclusion. A cage's painter left `design/painting/`
/// so the generic layer would stop importing the puzzle layer, and a file that
/// walks out of a gate's root is a file the gate stops seeing — so the root
/// followed it. `design/puzzle/spec/` stays out for `figurate_layout.dart`'s
/// reason one directory over: `board_geometry.dart` and
/// `letter_grid_geometry.dart` answer *where does a cell go* and return
/// positions they just computed, which is what a board is, and there is no
/// shadow within reach of either. The exclusion is the directory here rather
/// than a file because every inhabitant of that directory is that same case.
const List<ScanRoot> geometryGateRoots = <ScanRoot>[
  ScanRoot(prefix: 'design/widgets/'),
  ScanRoot(
    prefix: 'design/math/',
    excluding: <String>['design/math/spec/figurate_layout.dart'],
  ),
  ScanRoot(prefix: 'design/painting/'),
  ScanRoot(
    prefix: 'design/puzzle/',
    excluding: <String>['design/puzzle/spec/'],
  ),
  ScanRoot(prefix: 'features/'),
];

/// A hue selected by comparing two numbers.
///
/// The forbidden shape is `pct >= 90 ? BrandColors.green : BrandColors.pink`
/// written inline in a widget. It scatters the thresholds that give a hue its
/// meaning across every screen that draws one, and it is how a state ends up
/// communicated by hue alone — which BRD-1 forbids for a reader who cannot
/// separate the two. The remedy is a named level the adapter resolves in one
/// place.
///
/// **Relational operators only, deliberately.** `==` is excluded because a null
/// check or an enum comparison picking a colour is not a hue chosen by
/// *measurement*, and `verdict == null ? focus : error` is correct code in this
/// repo today. A threshold is what this is about.
///
/// **Two stated limits.** The left operand must be a plain identifier or member
/// chain, so a comparison assembled across two statements is invisible here —
/// as is one whose left side is a call. And a `switch` on an enum never matches,
/// which is intended: it is the remedy, not the defect.
///
/// **That shape of left operand is also what keeps generics out.** `<` and `>`
/// are type arguments far more often than comparisons in Dart, so a looser
/// pattern reports every `List<Widget>` and `Map<String, Color>` that happens
/// to sit near a colour.
final List<LiteralPattern> hueByComparisonPatterns = <LiteralPattern>[
  LiteralPattern(
    'a hue chosen by comparison',
    r'[A-Za-z_][A-Za-z0-9_.]*\s*(?:<=|>=|<|>)\s*[A-Za-z0-9_.]+\s*'
    r'\?[^;]{0,160}?(?:BrandColors|BrandColorRole)\b',
  ),
];

/// Where the hue-by-comparison gate looks: all of `app/lib/` except the tokens,
/// which are where a colour is legitimately named.
const ScanRoot hueGateRoot = ScanRoot(
  prefix: '',
  excluding: <String>['design/tokens/'],
);

/// The colour literal BRD-2b carves out by name.
///
/// `Colors.transparent` switches Material's surface tinting off and names no
/// hue. It is the one exception on disk, verbatim in `CLAUDE.md`.
const String permittedColorLiteral = 'Colors.transparent';

/// [hits] minus the one carve-out.
///
/// Kept apart from [findLiterals] so a gate can assert what its pattern matched
/// *before* anything was subtracted. A wrong pattern behind a long exclusion
/// list is green for the wrong reason.
List<LiteralHit> withoutPermitted(Iterable<LiteralHit> hits) => hits
    .where((LiteralHit hit) => hit.text != permittedColorLiteral)
    .toList();

/// Every literal of [patterns] in the files [roots] govern, comments stripped.
///
/// The match runs over the whole stripped source rather than line by line, so a
/// constructor broken across lines is still found; the line reported is the one
/// it starts on.
List<LiteralHit> findLiterals({
  required Map<String, String> sources,
  required Iterable<ScanRoot> roots,
  required Iterable<LiteralPattern> patterns,
}) {
  final List<LiteralHit> hits = <LiteralHit>[];
  for (final String file in selectFilesIn(roots, sources.keys)) {
    final String source = stripComments(sources[file]!);
    for (final LiteralPattern pattern in patterns) {
      for (final RegExpMatch match in pattern.matchesIn(source)) {
        hits.add(
          LiteralHit(
            file: file,
            line: _lineAt(source, match.start),
            text: _collapseWhitespace(match[0]!),
          ),
        );
      }
    }
  }
  hits.sort(_byFileThenLine);
  return hits;
}

int _byFileThenLine(LiteralHit a, LiteralHit b) {
  final int byFile = a.file.compareTo(b.file);
  return byFile != 0 ? byFile : a.line.compareTo(b.line);
}

int _lineAt(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

String _collapseWhitespace(String matched) =>
    matched.replaceAll(RegExp(r'\s+'), '');

/// A store held by a screen that should only report.
///
/// **Scoped to `features/puzzle/`, and the scope is the decision.** The two
/// puzzle screens commit differently — a value on a board, a word claimed —
/// so the moment a day is recorded differs while the *rule* does not. Putting
/// the store in both would put one IO decision in two places, free to diverge
/// the first time either screen changed. They report `onPractised`; the route
/// records.
///
/// **`RoundScreen` does take a store, and this gate deliberately does not cover
/// it.** There is one round screen, so the duplication argument does not apply
/// to it, and moving its store out is a change with its own reasoning and its
/// own tests — folding it in here would hide this one inside it. A gate scoped
/// to where the rule holds is worth more than a gate with a named violator in
/// its allowlist.
const List<ScanRoot> storeFreeScreenRoots = <ScanRoot>[
  ScanRoot(prefix: 'features/puzzle/'),
];

/// The two stores a screen must not hold, matched on identifier boundaries.
///
/// Whole names, because `DayLogStoreSpy` and `FakeDayLogStore` are test
/// doubles rather than the thing being forbidden, and a substring match would
/// report one.
final List<LiteralPattern> storePatterns = <LiteralPattern>[
  LiteralPattern('DayLogStore', r'(?<![A-Za-z0-9_$])DayLogStore(?![A-Za-z0-9_$])'),
  LiteralPattern(
    'SeriesCursorStore',
    r'(?<![A-Za-z0-9_$])SeriesCursorStore(?![A-Za-z0-9_$])',
  ),
];

/// Anywhere a wire submission could be built, minus where it is declared.
///
/// **`api/` is out because that is the class itself**: the two constructor
/// declarations in `api/sync.dart` match their own construction pattern, and a
/// root that reported them would name the definition as a violation. Everything
/// else under `app/lib/` is in, because the rule is about how many places
/// decide what a journalled answer looks like on the wire, and that number is
/// one wherever the file happens to sit.
const List<ScanRoot> submissionBuildingRoots = <ScanRoot>[
  ScanRoot(prefix: '', excluding: <String>['api/']),
];

/// Building an `AttemptSubmission`, by either door or by a generative
/// constructor somebody makes public again.
///
/// Two patterns rather than one so the report says which form it found. The
/// bare form should match nothing at all today — the generative constructor is
/// private — and it is here so that undoing *that* is caught by the same gate
/// as duplicating the mapping.
final List<LiteralPattern> submissionConstructionPatterns = <LiteralPattern>[
  LiteralPattern(
    'AttemptSubmission(',
    r'(?<![A-Za-z0-9_$])AttemptSubmission\s*\(',
  ),
  LiteralPattern(
    'AttemptSubmission.for…(',
    r'(?<![A-Za-z0-9_$])AttemptSubmission\s*\.\s*for[A-Za-z0-9_$]*\s*\(',
  ),
];

/// Anywhere the pack in play could be chosen, minus where the two things it is
/// chosen with are declared.
///
/// `content/model/pack.dart` declares `isExpiredAt` and
/// `content/model/issued_pack.dart` declares `readIssuedPack`; a root that
/// included them would report the definitions as violations. **The cost of the
/// exclusion, stated so it reads as a limit rather than being found as a bug**:
/// a call to either from inside those two files would go unseen. Neither makes
/// one today.
const List<ScanRoot> packChoiceRoots = <ScanRoot>[
  ScanRoot(
    prefix: '',
    excluding: <String>[
      'content/model/pack.dart',
      'content/model/issued_pack.dart',
    ],
  ),
];

/// Asking whether a pack may still be played, and turning what the server
/// issued into a pack at all.
///
/// Two patterns rather than one because they close different halves, and
/// **neither is the whole**. The window question is the one that was answered
/// twice and differently. Reading an issued pack is the only way a `Pack`
/// reaches this app from the server, so pinning its single caller keeps *the
/// parse* in one place — it does not make every server pack pass the window
/// question, because `packFrom` and `packInPlay` are independent exports and a
/// caller could reach for the first alone. What covers that is the routes' own
/// cases, not this scan.
final List<LiteralPattern> packChoicePatterns = <LiteralPattern>[
  LiteralPattern('isExpiredAt(', r'(?<![A-Za-z0-9_$])isExpiredAt\s*\('),
  LiteralPattern('readIssuedPack(', r'(?<![A-Za-z0-9_$])readIssuedPack\s*\('),
];
