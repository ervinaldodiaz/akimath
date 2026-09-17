import 'package:flutter/widgets.dart';

import '../../../../design/math/spec/es_mx_number.dart';
import '../../../../design/tokens/tokens.dart';
import '../../../../design/widgets/spec/term_visual.dart';
import '../../../../design/widgets/candy_surface.dart';

/// One value in a stimulus: a term, a matrix cell, half of an analogy pair.
///
/// **Four of the six families draw the same tile**, and they must — a hole in a
/// series and a hole in a grid are the same question, so a learner who has met
/// one should recognise the other without being taught twice. Duplicating the
/// widget per family is how that stops being true, one small divergence at a
/// time.
///
/// **The unknown tile is yellow and dashed, and that is not decoration.**
/// Solid-and-white means "this is given"; dashed-and-yellow means "this is the
/// hole". The pair has to read as different without relying on hue, because
/// deuteranopia collapses a good deal of the palette — so the outline pattern
/// carries the distinction and the fill only reinforces it. It is the same rule
/// the verdict ring already follows.
class StimulusTile extends StatelessWidget {
  /// A tile showing a value.
  const StimulusTile.given(int value, {super.key, this.size = _defaultSize})
      : _value = value,
        _state = TermState.given;

  /// The hole. It draws a `?` and never the value it hides — which is why it
  /// does not take one.
  const StimulusTile.unknown({super.key, this.size = _defaultSize})
      : _value = null,
        _state = TermState.unknown;

  static const double _defaultSize = 46;

  final int? _value;
  final TermState _state;

  /// Nominal numeral size, before text scaling.
  final double size;

  /// The tile: a fill, an outline and either a value or a `?`.
  ///
  /// **Its appearance is resolved once, by `resolveTermVisual`.** Choosing the
  /// hue here with a conditional is what
  /// `test/architecture/no_hue_by_comparison_test.dart` fails the build for,
  /// and it caught exactly that on the first run of the series view. Only the
  /// hole is dashed, so the pair still reads as different with the hue gone.
  ///
  /// The width is a floor rather than a fit, so a one-digit value and a
  /// three-digit value make a row that reads as a series rather than as tiles
  /// of assorted widths.
  ///
  /// `EsMxNumber` runs here rather than in the content: a thousand is `1 000`
  /// in es-MX, and a pack shipping the spelled string would have put that
  /// decision beyond the reach of any gate.
  @override
  Widget build(BuildContext context) {
    final TermVisual visual = resolveTermVisual(_state);
    final int? value = _value;

    return CandySurface(
      background: visual.background,
      borderRadius: BrandShape.radiusChip,
      borderWidth: BrandShape.borderWidth,
      shadowOffset: BrandShape.shadowPill,
      borderDash: visual.dash,
      padding: const EdgeInsets.symmetric(
        horizontal: BrandShape.space3,
        vertical: BrandShape.space2,
      ),
      child: SizedBox(
        width: size,
        child: Center(
          child: Text(
            value == null ? '?' : EsMxNumber.integer(value),
            maxLines: 1,
            style: BrandText.numeral(size * 0.7),
          ),
        ),
      ),
    );
  }
}
