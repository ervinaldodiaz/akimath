import 'package:flutter/widgets.dart';

import '../../../design/brand/aki.dart';
import '../../../design/math/spec/es_mx_number.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/candy_surface.dart';

/// `Guardar progreso` — the invitation to make an account, after playing.
///
/// **It asks rather than gates.** Nothing before this screen has needed an
/// account and nothing after it does either: unlinked play is entirely offline
/// (ADR 0002), so *"Después"* is a real answer and not a delay.
///
/// **The sentence under the tiles is the whole argument**, and it is true as
/// written: without an account the day log and the streak live in
/// `shared_preferences` on this handset and go with the app.
///
/// The design draws three tiles; this screen draws the ones with a source —
/// see [_tiles].
class SaveProgressScreen extends StatelessWidget {
  const SaveProgressScreen({
    super.key,
    required this.challenges,
    required this.days,
    required this.onLater,
    this.onCreateAccount,
  });

  /// How many challenges this player has actually answered.
  final int challenges;

  /// How many days they have practised.
  final int days;

  /// Moves on without an account.
  final VoidCallback onLater;

  /// Opens the account flow, when there is one.
  ///
  /// **Null draws no button** (DR-P2, the same reading as the profile drawing
  /// no account row in a build with no auth URL): a control that goes nowhere
  /// is worse than no control, and `Después` is still a way on.
  final VoidCallback? onCreateAccount;

  static const double _akiWidth = 118;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? create = onCreateAccount;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandShape.space4,
        vertical: BrandShape.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Spacer(),
          Center(child: Aki(width: _akiWidth, semanticLabel: 'Aki')),
          const SizedBox(height: BrandShape.space4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '¿TE LO GUARDO?',
              textAlign: TextAlign.center,
              style: BrandText.sectionTitle(size: 42),
            ),
          ),
          const SizedBox(height: BrandShape.space4),
          _tiles(),
          const SizedBox(height: BrandShape.space4),
          Text(
            'Si cierras la app sin cuenta, esto se queda en este teléfono.',
            textAlign: TextAlign.center,
            style: BrandText.body(),
          ),
          const Spacer(),
          if (create != null) ...<Widget>[
            BrandButton.primary(label: 'Crear cuenta', onPressed: create),
            const SizedBox(height: BrandShape.space3),
          ],
          BrandButton.secondary(label: 'Después', onPressed: onLater),
        ],
      ),
    );
  }

  /// The design's three tiles, minus the ones with nothing behind them.
  ///
  /// `RETOS` and the day count are facts about this handset. The design's
  /// middle tile is `RATING 1 248` and it is **absent**: rating never runs in
  /// Dart and `GET /me/standing` answers one per skill, so there is no number
  /// to put there — it was an invented constant until 2026-09-02. The row is
  /// as long as the facts are, which is the shape `4.1`'s tile row already has:
  /// *"one tile is as legitimate as three — it is the shipping build"*.
  ///
  /// **On the run that ships, that is exactly one tile.** `OnboardingFlow`
  /// always passes `days: 0` — neither the teaching item nor the probe records
  /// a day — so a first-time player sees a single full-width `RETOS`, and a
  /// player who reaches this screen with days behind them sees two.
  ///
  /// At zero days the tile is **absent, not a tile reading zero** — the same
  /// reading as `HISTORIAL` with nothing in it, and the figure shown has to be
  /// the figure the store will yield one tap later.
  ///
  /// The day tile is **yellow**, which is what the design fills; the filled
  /// tile is the one the screen is about, the same hierarchy `4.1` draws
  /// between its two headline cards.
  Widget _tiles() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _tile(
                label: 'RETOS',
                value: EsMxNumber.integer(challenges),
                background: BrandColors.surface,
              ),
            ),
            if (days > 0) ...<Widget>[
              const SizedBox(width: BrandShape.space2),
              Expanded(
                child: _tile(
                  label: days == 1 ? 'DÍA' : 'DÍAS',
                  value: EsMxNumber.integer(days),
                  background: BrandColors.yellow,
                ),
              ),
            ],
          ],
        ),
      );

  /// One tile, in the design's raised treatment.
  ///
  /// On the filled tile the muted eyebrow loses its contrast, so the label
  /// takes the ink the design gives it there — the same reading `4.1`'s
  /// headline pair already makes.
  Widget _tile({
    required String label,
    required String value,
    required Color background,
  }) =>
      CandySurface(
        background: background,
        borderRadius: BrandShape.radiusStatTileRaised,
        shadowOffset: BrandShape.shadowTile,
        padding: const EdgeInsets.symmetric(
          horizontal: BrandShape.space2,
          vertical: BrandShape.space3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: BrandText.numeral(26)),
            ),
            const SizedBox(height: BrandShape.space1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: BrandText.eyebrow(
                  color: background == BrandColors.surface
                      ? BrandColors.muted
                      : BrandColors.ink,
                  size: 11,
                  letterSpacing: 0.06,
                ),
              ),
            ),
          ],
        ),
      );
}
