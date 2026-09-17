import 'package:flutter/material.dart';

import '../../../design/icons/brand_icon.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/candy_surface.dart';
import '../../../design/widgets/stat_tile.dart';
import '../policy/pause.dart';

/// `Pausa` — the board covered, not erased.
///
/// **It covers the board rather than blurring it.** The design annotates the
/// screen *"tablero tapado, no borroso"*, which is also what BRD-2a requires:
/// there is no `BackdropFilter` in this app and this is not the screen that
/// introduces one. The entry behind it is untouched, so resuming is a rebuild
/// and not a restore.
///
/// **There is no clock on it, and that is the design's own decision as much as
/// the rulebook's.** `Pausa` is drawn with a cell count and a format name;
/// `Puzzle resuelto`, one screen away, shows `11:24 TIEMPO`. `PauseSummary`
/// has nowhere to put a duration, so this screen cannot print one.
///
/// **Nothing here survives the app closing**, which is why the second control
/// is not the design's *Guardar y salir*: that label promises a board that
/// comes back and nothing writes one to disk. What the copy claims is exactly
/// what is true — the board is here while the player stays.
class PausedBoardView extends StatelessWidget {
  const PausedBoardView({
    super.key,
    required this.summary,
    required this.onResume,
    required this.onLeave,
  });

  final PauseSummary summary;

  /// Back to the board, exactly as it was.
  final VoidCallback onResume;

  /// Out of the board, losing what is on it.
  final VoidCallback onLeave;

  /// The rounded square the pause mark sits in, from the design.
  static const double _markSide = 76;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandShape.space5,
            vertical: BrandShape.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: SingleChildScrollView(child: _band())),
              const SizedBox(height: BrandShape.space3),
              BrandButton.primary(label: 'Reanudar', onPressed: onResume),
              const SizedBox(height: BrandShape.space2),
              BrandButton.secondary(
                label: 'Salir del tablero',
                onPressed: onLeave,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The heading, the cover and the two tiles — everything above the controls.
  ///
  /// **The band scrolls and the buttons do not.** At `textScaler` 1.3 on the
  /// notched viewport the heading, the card and the two tiles are taller than
  /// what is left after the controls, and the controls are the reason a player
  /// opened this.
  Widget _band() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(height: BrandShape.space5),
        Text(
          'EN PAUSA',
          textAlign: TextAlign.center,
          style: BrandText.sectionTitle(size: 48),
        ),
        const SizedBox(height: BrandShape.space5),
        _cover(),
        const SizedBox(height: BrandShape.space3),
        _tiles(),
        const SizedBox(height: BrandShape.space4),
      ],
    );
  }

  /// What is over the board: a mark and a sentence, and no board.
  Widget _cover() {
    return CandySurface(
      padding: const EdgeInsets.all(BrandShape.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CandySurface(
            width: _markSide,
            height: _markSide,
            background: BrandColors.cream,
            borderRadius: BrandShape.radiusCardSmall,
            shadowOffset: Offset.zero,
            alignment: Alignment.center,
            child: const BrandIcon(BrandGlyph.pause, size: 30),
          ),
          const SizedBox(height: BrandShape.space3),
          Text(
            'Tu tablero sigue aquí mientras no salgas.',
            textAlign: TextAlign.center,
            style: BrandText.caption(size: 14),
          ),
        ],
      ),
    );
  }

  Widget _tiles() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: StatTile(
              label: 'DE ${summary.total} CELDAS',
              value: StatValue('${summary.filled}'),
              variant: StatTileVariant.compact,
            ),
          ),
          const SizedBox(width: BrandShape.space2),
          Expanded(
            child: StatTile(
              label: summary.sizeLabel,
              value: _formatNameFittedToTheTile(),
              variant: StatTileVariant.compact,
            ),
          ),
        ],
      ),
    );
  }

  /// The format's name, **scaled down rather than ellipsised.**
  ///
  /// `CUADRO MÁGICO` is the longest name and it is the whole point of the tile;
  /// a tile reading `CUADRO M…` names nothing.
  Widget _formatNameFittedToTheTile() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: StatValue(summary.formatName, size: 20),
    );
  }
}
