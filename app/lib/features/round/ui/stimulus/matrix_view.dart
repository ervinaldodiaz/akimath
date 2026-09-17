import 'package:flutter/widgets.dart';

import '../../../../design/tokens/tokens.dart';
import 'stimulus_tile.dart';

/// The 2×2 or 3×3 grid with one cell missing.
///
/// The third item family, and the first that asks a question in two directions
/// at once: the rule runs along the rows *and* down the columns, and the hole
/// is where they meet. A multiplication table is the clearest case — given
/// eight of nine cells, the ninth is over-determined, which is what makes it
/// solvable rather than a guess.
///
/// **Square by construction.** The payload declares `size` separately from the
/// cell list precisely so a truncated pack is a rejection rather than a
/// silently smaller grid; the reader enforces `cells.length == size * size`, so
/// by the time this widget runs the row split cannot be ragged.
///
/// No margin arrows yet. The design draws pink ones down the right and along
/// the bottom to say "read across, read down", and they want the stroke-icon
/// layer that `docs/IMPLEMENTATION-PLAN.md` still lists as unbuilt. A grid with
/// one hole reads without them; a grid with arrows borrowed from Material would
/// read as a different product.
class MatrixView extends StatelessWidget {
  const MatrixView({
    super.key,
    required this.cells,
    required this.size,
    required this.unknownIndex,
    this.tileSize = 46,
  });

  /// Every cell in reading order — left to right, then top to bottom —
  /// including the true value of the hidden one.
  final List<int> cells;

  /// The grid's edge length. `cells.length` is its square.
  final int size;

  /// Which cell is blank. The value at this index is never rendered.
  final int unknownIndex;

  /// Nominal numeral size, before text scaling.
  final double tileSize;

  /// The grid, row by row.
  ///
  /// `mainAxisSize.min` on both axes, because the caller wraps this in a
  /// scaling `FittedBox` and an unbounded column inside one is an overflow
  /// rather than a smaller grid.
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int row = 0; row < size; row++) ...<Widget>[
          if (row > 0) const SizedBox(height: BrandShape.space2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int column = 0; column < size; column++) ...<Widget>[
                if (column > 0) const SizedBox(width: BrandShape.space2),
                _cell(row * size + column),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _cell(int index) => index == unknownIndex
      ? StimulusTile.unknown(size: tileSize)
      : StimulusTile.given(cells[index], size: tileSize);
}
