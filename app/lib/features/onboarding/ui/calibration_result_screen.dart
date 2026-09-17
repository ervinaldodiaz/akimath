import 'package:flutter/widgets.dart';

import '../../../design/brand/aki.dart';
import '../../../design/math/spec/es_mx_number.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/stat_tile.dart';
import '../policy/calibration.dart';

/// `Calibración resultado` — where the probe leaves you.
///
/// **Two of the three things the design draws here do not exist, and both are
/// absent rather than approximated.**
///
/// - The **count and the time are real**. Every item was graded on the device
///   by the same `gradeItem` the round uses, and the clock was the probe's own.
/// - The **rating card is absent.** The design draws `RATING 1 248` under the
///   headline. Rating never runs in Dart, and `GET /me/standing` answers a
///   rating **per skill** — no single number over a list of Glicko ratings is a
///   fact about a player, which is the same reason `Perfil`'s rating slot is
///   empty rather than averaged into existence. It was drawn from an invented
///   constant until 2026-09-02. Absent, not a dash and not a zero (DR-P2): a
///   figure with no source cannot be shown as a figure waiting for one.
/// - The **skill map is absent.** The design draws four nodes, two lit, one at
///   `38%` and one dashed. Every one of those is a placement, a placement needs
///   a placement algorithm, and there is none. A tree drawn from nothing would
///   be the one claim this screen must not make, so the slot carries the
///   figures the probe actually produced instead.
///
/// The design's own sentence — *"No es calificación. Es de dónde salimos"* —
/// is what keeps the count from reading as the grade `0.4` promised it is not,
/// and it sits directly under the figures for that reason. With the rating gone
/// it is the last line on the screen and it is still true of what is left: the
/// count is where you started, not a mark.
class CalibrationResultScreen extends StatelessWidget {
  const CalibrationResultScreen({
    super.key,
    required this.outcome,
    required this.onEnter,
  });

  /// What the probe measured. Only drawn when it has something to report —
  /// `OnboardingFlow` skips this screen entirely otherwise.
  final CalibrationOutcome outcome;

  /// Leaves for whatever comes next.
  ///
  /// **The screen does not know where.** The design's label says *mapa* and the
  /// app's root is the home, which is a wiring question and not this widget's.
  final VoidCallback onEnter;

  static const double _akiWidth = 132;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandShape.space4,
        vertical: BrandShape.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _scrollingReadableHalf(),
          const SizedBox(height: BrandShape.space4),
          BrandButton.primary(label: 'Entrar a mi mapa', onPressed: onEnter),
        ],
      ),
    );
  }

  /// Everything above the button, which scrolls while the button does not.
  ///
  /// This screen stacks a drawing, a display line, the cards and a paragraph,
  /// and it cleared the 390×844 overflow gate at `textScaler` 1.3 by about four
  /// percent — measured: it overflowed at 1.35 on macOS and at 1.30 on CI's
  /// Ubuntu, whose glyph advances are wider. A layout that fits by a pixel on
  /// one toolchain does not fit on another, and the runner is the authority.
  /// Scrolling removes the ceiling instead of moving it: nothing scrolls while
  /// it fits, and there is no arrangement of fonts or text sizes that can
  /// overflow it.
  ///
  /// Keeping the button **outside** the scroll view is the other half. An
  /// overflowing `Column` squeezes its children, which is how a 62px control
  /// measures under 48 on the rendered screen and takes the touch-target gate
  /// with it.
  ///
  /// The `minHeight` is what keeps it centred while it fits and scrolled once
  /// it does not, rather than pinned to the top with a gap under it at 1.0.
  Widget _scrollingReadableHalf() => Expanded(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) =>
              SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Center(
                    child: Aki(
                      width: _akiWidth,
                      pose: AkiPose.correct,
                      semanticLabel: 'Aki',
                    ),
                  ),
                  const SizedBox(height: BrandShape.space4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'AQUÍ EMPIEZAS',
                      style: BrandText.sectionTitle(size: 44),
                    ),
                  ),
                  const SizedBox(height: BrandShape.space4),
                  _measured(),
                  const SizedBox(height: BrandShape.space4),
                  Text(
                    'No es calificación. Es de dónde salimos, y se mueve '
                    'todos los días.',
                    textAlign: TextAlign.center,
                    style: BrandText.body(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// The two figures the probe actually produced.
  ///
  /// `0.7`'s three-tile idiom from the same document, with two tiles because
  /// there are two true figures — a third would have to be invented, which is
  /// the whole argument of this screen.
  Widget _measured() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _figure(
              label: 'ACIERTOS',
              value: EsMxNumber.ratio(outcome.correct, outcome.answered),
            ),
            const SizedBox(width: BrandShape.space2),
            _figure(
              label: 'TIEMPO',
              value: EsMxNumber.elapsed(outcome.elapsed),
            ),
          ],
        ),
      );

  /// One measured figure, in a tile that takes half the row.
  ///
  /// **`scaleDown`, because a tile is half a screen wide.** `10 / 10` and an
  /// hour-long `64:09` are the widest figures these two can hold, and a numeral
  /// that does not fit wraps — which grows the row and overflows the screen
  /// rather than the tile. The same shape that overflowed `4.1`'s tile row.
  Widget _figure({required String label, required String value}) => Expanded(
        child: StatTile(
          label: label,
          value: FittedBox(
            fit: BoxFit.scaleDown,
            child: StatValue(value, size: 24),
          ),
        ),
      );
}
