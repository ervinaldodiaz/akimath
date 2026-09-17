import 'package:flutter/widgets.dart';

import '../../../../design/icons/brand_icon.dart';
import '../../../../design/tokens/tokens.dart';
import '../../../../design/widgets/stat_pill.dart';
import 'stimulus_tile.dart';

/// `2 › 4 · como · 5 › ?` — two pair-cards joined by a bridge.
///
/// The fourth family, and the only one whose question is about a *relation*
/// rather than a value: the two pairs share a rule, and the hole is whichever
/// of the four terms is missing. Finding it means reading the first pair, not
/// continuing it.
///
/// **`unknown_index` walks all four terms in reading order** — first pair's
/// left, first pair's right, second pair's left, second pair's right — which is
/// the frozen convention and is why one bound covers both cards. The hole is
/// usually the last term, but it does not have to be, and putting it on a term
/// of the *first* pair is a genuinely different question: it asks the learner
/// to run the rule backwards from the pair that is intact.
class AnalogyView extends StatelessWidget {
  const AnalogyView({
    super.key,
    required this.terms,
    required this.unknownIndex,
    this.size = 46,
  });

  /// The four terms in reading order, including the hidden one's true value.
  final List<int> terms;

  /// Which term is blank. The value at this index is never rendered.
  final int unknownIndex;

  /// Nominal numeral size, before text scaling.
  final double size;

  /// The bridge. es-MX, and the only player-visible word on the screen.
  ///
  /// `como` and not `es a`: the whole reads *"2 es a 4 **como** 5 es a ?"*, and
  /// the chevrons already carry the two `es a`s. Spelling all three out would
  /// put more Spanish on the prompt than arithmetic.
  ///
  /// It is set in the eyebrow face rather than the numeral one: the bridge is a
  /// word joining two statements and must not compete with the four figures it
  /// sits between.
  static const String bridgeLabel = 'como';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _pair(0),
        const SizedBox(width: BrandShape.space3),
        StatPill(
          size: StatPillSize.hero,
          height: size,
          background: BrandColors.surface,
          child: Text(
            bridgeLabel.toUpperCase(),
            style: BrandText.eyebrow(size: size * 0.34),
          ),
        ),
        const SizedBox(width: BrandShape.space3),
        _pair(1),
      ],
    );
  }

  /// One card: two terms and the chevron that reads as *es a*.
  Widget _pair(int pair) {
    final int left = pair * 2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _tile(left),
        SizedBox(
          width: size * 0.7,
          child: Center(
            child: BrandIcon(
              BrandGlyph.mapsTo,
              size: size * 0.62,
              color: BrandColors.ink,
            ),
          ),
        ),
        _tile(left + 1),
      ],
    );
  }

  Widget _tile(int index) => index == unknownIndex
      ? StimulusTile.unknown(size: size)
      : StimulusTile.given(terms[index], size: size);
}
