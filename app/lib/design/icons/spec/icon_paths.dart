/// Every glyph's geometry, transcribed from the design documents.
///
/// **PURE** — data and `dart:ui`, the same latitude `aki_spec.dart` takes.
///
/// **Transcribed, never redrawn.** Each `d` below is the byte-for-byte string
/// from the design's own SVG, and so are the viewBox, the stroke width and the
/// caps. An icon drawn by eye is a fork of the design that nobody knows exists,
/// which is why this file stores strings rather than `lineTo` calls: the spec
/// and the document can be compared by reading them side by side.
///
/// Sources, all in the Claude Design project `11887b49`:
/// * `AkiMath Perfil y Estados.dc.html` — back, forward, check, alert, gear,
///   flame, wifiOff, mapsTo
/// * `AkiMath Reactivos y Puzzles.dc.html` — close, pause, undo, hint, pencil
/// * `AkiMath Primera Vez y Cuenta.dc.html` — backspace, submit
/// * `AkiMath Pantallas Base.dc.html` — padlock
///
/// **No icon package.** Every dependency is a DEP-1 decision — it widens the
/// supply-chain surface and costs an audit again at every version (ADR 0003);
/// and these carry their own stroke weights — submit at 3.2 against backspace
/// at 2.6 — which no general set reproduces.
library;

import 'dart:ui';

import 'brand_glyph.dart';
import 'svg_path.dart';

/// One glyph: what to draw, how big its own coordinate space is, and how it is
/// stroked.
///
/// **The stroke belongs to the glyph, not to the renderer.** The design assigns
/// weight per mark — the submit arrow is deliberately chunkier than the
/// backspace beside it on the same keypad — so a single global weight would
/// flatten a distinction somebody made on purpose.
class IconSpec {
  const IconSpec({
    required this.d,
    required this.viewBox,
    required this.strokeWidth,
    this.round = true,
  });

  /// The verbatim `d` attribute, one entry per `<path>` in the source SVG.
  final List<String> d;

  /// The coordinate space [d] is expressed in.
  ///
  /// **Not always square.** `mapsTo` is 30×24 in the design, and squaring it
  /// would either distort the arrow or letterbox it.
  final Size viewBox;

  /// The stroke, in viewBox units.
  final double strokeWidth;

  /// Whether the ends and joins are rounded.
  ///
  /// One flag rather than two. Every glyph in the set that rounds one rounds
  /// the other where both apply, and the handful that name only `linecap` or
  /// only `linejoin` do so because the other has nothing to act on — a straight
  /// stroke has no join, a closed outline has no visible cap.
  final bool round;

  /// The geometry, ready to stroke.
  List<Path> get paths => <Path>[for (final String each in d) parseSvgPath(each)];
}

/// The transcription, by name.
const Map<BrandGlyph, IconSpec> iconPaths = <BrandGlyph, IconSpec>{
  BrandGlyph.back: IconSpec(
    d: <String>['M14 5l-7 7 7 7'],
    viewBox: Size(24, 24),
    strokeWidth: 3,
  ),
  BrandGlyph.forward: IconSpec(
    d: <String>['M9 5l7 7-7 7'],
    viewBox: Size(24, 24),
    strokeWidth: 3,
  ),
  BrandGlyph.check: IconSpec(
    d: <String>['M4 11l4 4 8-9'],
    viewBox: Size(20, 20),
    strokeWidth: 3.4,
  ),
  BrandGlyph.alert: IconSpec(
    d: <String>['M10 4v8M10 15h.01'],
    viewBox: Size(20, 20),
    strokeWidth: 3,
  ),
  BrandGlyph.close: IconSpec(
    d: <String>['M6 6l12 12M18 6L6 18'],
    viewBox: Size(24, 24),
    strokeWidth: 3,
  ),
  BrandGlyph.gear: IconSpec(
    // The hub is a `<circle cx="12" cy="12" r="3">` in the source. A circle is
    // an arc pair, written here as one because the parser takes paths and the
    // alternative is a second shape kind for one glyph.
    d: <String>[
      'M12 3v3M12 18v3M3 12h3M18 12h3'
          'M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1',
      'M9 12a3 3 0 0 1 6 0a3 3 0 0 1-6 0Z',
    ],
    viewBox: Size(24, 24),
    strokeWidth: 2.6,
  ),
  BrandGlyph.flame: IconSpec(
    d: <String>[
      'M12 3c3 4 6 5.5 6 9a6 6 0 0 1-12 0c0-2 1-3.2 2.5-4.5C10 9.5 11 7 12 3Z',
    ],
    viewBox: Size(24, 24),
    strokeWidth: 2.4,
  ),
  BrandGlyph.wifiOff: IconSpec(
    d: <String>[
      'M3 7a13 13 0 0 1 14 0M6 11a8 8 0 0 1 8 0M10 15h.01',
      'M3 3l14 14',
    ],
    viewBox: Size(20, 20),
    strokeWidth: 2.4,
  ),
  BrandGlyph.mapsTo: IconSpec(
    d: <String>['M3 12h20M17 5l6 7-6 7'],
    // **30×24, and that is the design.** The one non-square glyph in the set.
    viewBox: Size(30, 24),
    strokeWidth: 3,
  ),
  BrandGlyph.backspace: IconSpec(
    d: <String>['M9 5h13v16H9L2 13Z', 'M13 10l6 6M19 10l-6 6'],
    viewBox: Size(26, 26),
    strokeWidth: 2.6,
  ),
  BrandGlyph.submit: IconSpec(
    d: <String>['M4 12h14M12 6l6 6-6 6'],
    viewBox: Size(24, 24),
    // Chunkier than the backspace it sits beside, on purpose.
    strokeWidth: 3.2,
  ),
  BrandGlyph.pause: IconSpec(
    d: <String>['M9 5v14M15 5v14'],
    viewBox: Size(24, 24),
    strokeWidth: 3.2,
  ),
  BrandGlyph.undo: IconSpec(
    d: <String>['M4 8h9a5 5 0 1 1 0 10H8', 'M8 4L4 8l4 4'],
    viewBox: Size(24, 24),
    strokeWidth: 2.6,
  ),
  BrandGlyph.hint: IconSpec(
    d: <String>[
      'M9 18h6M10 21h4',
      'M12 3a6 6 0 0 0-3.5 10.9V15h7v-1.1A6 6 0 0 0 12 3Z',
    ],
    viewBox: Size(24, 24),
    strokeWidth: 2.6,
  ),
  BrandGlyph.pencil: IconSpec(
    d: <String>['M16 3l5 5-11 11H5v-5L16 3Z'],
    viewBox: Size(24, 24),
    strokeWidth: 2.6,
  ),
  BrandGlyph.navHome: IconSpec(
    d: <String>['M4 12 L13 4 L22 12 V22 H4 Z'],
    viewBox: Size(26, 26),
    strokeWidth: 2.6,
  ),
  BrandGlyph.navSkills: IconSpec(
    // Three nodes and the two edges between them. The circles are `<circle>`
    // elements in the source, written as arc pairs for the same reason the
    // gear's hub is.
    d: <String>[
      'M10 8.6 L16 10.6M16.6 14.6 L11.6 18',
      'M3.6 7a3.4 3.4 0 0 1 6.8 0a3.4 3.4 0 0 1-6.8 0Z',
      'M15.6 12a3.4 3.4 0 0 1 6.8 0a3.4 3.4 0 0 1-6.8 0Z',
      'M5.6 20a3.4 3.4 0 0 1 6.8 0a3.4 3.4 0 0 1-6.8 0Z',
    ],
    viewBox: Size(26, 26),
    strokeWidth: 2.6,
  ),
  BrandGlyph.navProgress: IconSpec(
    d: <String>['M5 21V13M13 21V6M21 21V16'],
    viewBox: Size(26, 26),
    strokeWidth: 2.6,
  ),
  BrandGlyph.navProfile: IconSpec(
    d: <String>[
      'M5 22c1.6-4 4.4-5.6 8-5.6s6.4 1.6 8 5.6',
      'M8.8 9a4.2 4.2 0 0 1 8.4 0a4.2 4.2 0 0 1-8.4 0Z',
    ],
    viewBox: Size(26, 26),
    strokeWidth: 2.6,
  ),
  BrandGlyph.padlock: IconSpec(
    // The shackle is a path and the body a `<rect x="4" y="9" w="12" h="8"
    // rx="2">`, written out because the parser takes paths.
    d: <String>[
      'M7 9V7a3 3 0 0 1 6 0v2',
      'M6 9h8a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2Z',
    ],
    viewBox: Size(20, 20),
    strokeWidth: 2.6,
  ),
};
