import 'package:flutter/material.dart';

import '../../../design/brand/aki.dart';
import '../../../design/math/spec/es_mx_number.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/stat_tile.dart';

/// What a player sees when a puzzle is finished.
///
/// **A third screen, not a reused verdict** (design D1). `VerdictScreen` needs
/// a `Verdict`, and passing `Verdict.correct` would put a solid ring and
/// "¡Bien hecho!" on a screen whose alternative never existed: a puzzle has no
/// wrong ending, only an unfinished one. `SeriesSummaryScreen` needs `correct`
/// out of `total`, which a puzzle has neither of. The *parts* are reused; the
/// shape is not.
///
/// **It carries no `VerdictRing`, and that is the design** (D2). BRD-1 asks
/// that success and error be distinguishable by shape rather than hue, and this
/// screen has one state — there is nothing here for a mark to contrast against.
/// Said out loud because the absence would otherwise read as an omission beside
/// two screens that have one.
///
/// **Two figures, both local.** Time and streak, the same pair the verdict
/// screens show and for the same reason: F3 has no sync, so a number here could
/// be contradicted later.
class PuzzleSolvedScreen extends StatelessWidget {
  const PuzzleSolvedScreen({
    super.key,
    required this.format,
    required this.elapsed,
    required this.streakDays,
    required this.onDone,
  });

  /// What the player just beat, from `puzzleName` — five formats are reachable
  /// from one home, and "you finished a puzzle" does not say which.
  final String format;

  /// Measured by the route from the moment the puzzle opened (design D3), and
  /// shown only here (`req-quiet-timing`).
  final Duration elapsed;

  /// A local calendar fact, from `StreakPolicy`.
  final int streakDays;

  final VoidCallback onDone;

  /// Aki's celebration is the same size the verdict screen draws her.
  static const double _akiWidth = 182;
  static const double _bandHeight = 156;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandShape.space4,
            vertical: BrandShape.space3,
          ),
          child: Column(
            children: <Widget>[
              const Spacer(),
              SizedBox(
                height: _bandHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: <Widget>[
                    Aki(
                      width: _akiWidth,
                      pose: AkiPose.correct,
                      semanticLabel: 'Aki celebrando',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: BrandShape.space4),
              Text('¡Lo armaste!', style: BrandText.cardTitle(size: 22)),
              const SizedBox(height: 2),
              Text(format, style: BrandText.eyebrow()),
              const SizedBox(height: BrandShape.space5),
              _tiles(),
              const Spacer(),
              BrandButton.primary(label: 'Seguir', onPressed: onDone),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tiles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _timeTile(),
        const SizedBox(width: BrandShape.space3),
        _streakTile(),
      ],
    );
  }

  /// How long the sitting took, printed as **`elapsed` and not `seconds`.**
  ///
  /// The verdict screens print `4,2 s` because an item is a reaction and a
  /// tenth of a second is the interesting part. A puzzle is a sitting: an hour
  /// of Kakuro reads `3 849,0 s`, which is not a time a person can take in —
  /// and it overflows the tile at `textScaler` 1.3, which is how this was found.
  Widget _timeTile() {
    return StatTile(
      label: 'TIEMPO',
      value: StatValue(
        EsMxNumber.elapsed(elapsed),
        size: StatTileVariant.raised.valueSize,
      ),
      variant: StatTileVariant.raised,
    );
  }

  Widget _streakTile() {
    return StatTile(
      label: 'RACHA',
      value: StatValue(
        EsMxNumber.integer(streakDays),
        size: StatTileVariant.raised.valueSize,
      ),
      variant: StatTileVariant.raised,
    );
  }
}
