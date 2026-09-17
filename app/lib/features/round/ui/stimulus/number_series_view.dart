import 'package:flutter/widgets.dart';

import '../../../../design/tokens/tokens.dart';
import 'stimulus_tile.dart';

/// `2 · ? · 18 · 54` — the number-series stimulus.
///
/// The second item family the app can draw, and the first that is not an
/// expression. Everything about it is a row of tiles: the terms the player is
/// given, and the one they have to supply.
///
/// **The hole is a position, not the end.** The payload carries every term —
/// including the true value of the hidden one, which offline grading and the
/// error screen's replay both need on the device — and names the index that is
/// blank. So this widget's first responsibility is a negative one: it must not
/// draw `terms[unknownIndex]`.
///
/// The tile itself is [StimulusTile], shared with the grid, because a hole in a
/// series and a hole in a matrix are the same question and a learner should not
/// have to meet it twice.
class NumberSeriesView extends StatelessWidget {
  const NumberSeriesView({
    super.key,
    required this.terms,
    required this.unknownIndex,
    this.size = 46,
  });

  /// Every term in order, including the hidden one's true value.
  final List<int> terms;

  /// Which term is blank. The value at this index is never rendered.
  final int unknownIndex;

  /// Nominal numeral size, before text scaling.
  final double size;

  /// The terms in a single row.
  ///
  /// **One row, and the caller scales it.** `RoundScreen` draws every prompt
  /// inside a `FittedBox(scaleDown)`, which is what lets a long arithmetic
  /// expression shrink instead of clipping; a series is the same problem with
  /// more tiles. Wrapping onto a second line was the first attempt and it
  /// looked like two series rather than one.
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < terms.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: BrandShape.space2),
          if (i == unknownIndex)
            StimulusTile.unknown(size: size)
          else
            StimulusTile.given(terms[i], size: size),
        ],
      ],
    );
  }
}
