import 'package:flutter/widgets.dart';

import '../../../../design/math/spec/figurate_layout.dart';
import '../../../../design/tokens/tokens.dart';
import '../../../../design/widgets/spec/term_visual.dart';
import '../../../../design/widgets/candy_surface.dart';

/// Growing dot figures with one of them missing.
///
/// ```
/// ·      · ·      · · ·
///       ·        · ·        [?]
/// ```
///
/// The sixth and last frozen family, and the only one whose stimulus is not a
/// number at all: the learner counts the dots, finds the rule the counts follow
/// — 1, 3, 6, 10 are the triangular numbers — and types the count of the figure
/// that is missing. The answer is a number; the question is a picture.
///
/// **The arrangement is this app's decision, not the pack's.** The payload
/// carries only a dot count, so `figurateLayout` chooses the figure, and that
/// choice *is* the puzzle: six drawn as a 3×2 block leaves nothing to continue.
/// It lives in `design/math/spec/` as pure geometry with no `Canvas` anywhere
/// near it, which is also why this widget composes offsets it was handed rather
/// than computing any — `no_geometry_literal_test` scans `features/` for
/// exactly that.
class FigurateView extends StatelessWidget {
  const FigurateView({
    super.key,
    required this.dotCounts,
    required this.unknownIndex,
    this.boxSize = 52,
  });

  /// The dot count of each figure in order, including the hidden one's true
  /// count. Strictly increasing — the reader refuses anything else, because a
  /// flat or falling run has no figurate rule to find.
  final List<int> dotCounts;

  /// Which figure is blank. Its dots are never drawn.
  final int unknownIndex;

  /// The square each figure is drawn inside. The design's box.
  final double boxSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < dotCounts.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: BrandShape.space2),
          _figure(i),
        ],
      ],
    );
  }

  /// One box: either the figure's dots, or the `?` that stands for the hole.
  ///
  /// The hole draws a `?` rather than an empty box, because a blank square
  /// beside three dotted ones reads as a figure of zero rather than as the
  /// question.
  Widget _figure(int index) {
    final bool unknown = index == unknownIndex;
    final TermVisual visual = resolveTermVisual(
      unknown ? TermState.unknown : TermState.given,
    );

    return CandySurface(
      background: visual.background,
      borderRadius: BrandShape.radiusChip,
      borderWidth: BrandShape.borderWidth,
      shadowOffset: BrandShape.shadowPill,
      borderDash: visual.dash,
      padding: const EdgeInsets.all(BrandShape.space2),
      child: SizedBox(
        width: boxSize,
        height: boxSize,
        child: unknown
            ? Center(
                child: Text('?', style: BrandText.numeral(boxSize * 0.62)),
              )
            : CustomPaint(
                painter: FigurateDotsPainter(figurateLayout(dotCounts[index])),
              ),
      ),
    );
  }
}

/// Paints one figure's dots. The adapter half — every number it uses came out
/// of [figurateLayout].
///
/// Named rather than private so a test can read back the [layout] each box was
/// handed. Four boxes sharing one layout would draw four identical figures,
/// leaving no rule to find, and every count assertion would still pass.
///
/// The shortest side scales **both** axes, so a figure keeps the shape the spec
/// laid out even when the box it is given is not square.
@visibleForTesting
class FigurateDotsPainter extends CustomPainter {
  const FigurateDotsPainter(this.layout);

  final FigurateLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleForBothAxes = size.shortestSide;
    final Paint paint = Paint()..color = BrandColors.ink;

    for (final Offset dot in layout.dots) {
      canvas.drawCircle(
        dot.scale(scaleForBothAxes, scaleForBothAxes),
        layout.radius * scaleForBothAxes,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FigurateDotsPainter oldDelegate) =>
      oldDelegate.layout != layout;
}
