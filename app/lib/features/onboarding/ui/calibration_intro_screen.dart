import 'package:flutter/widgets.dart';

import '../../../design/brand/aki.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/candy_surface.dart';

/// `Calibración intro` — what the probe is, before it starts.
///
/// **Never the word *prueba*.** The design says so in its own label, and the
/// reason is the product rather than the wording: a player who reads this as a
/// test performs, and a probe measures nothing useful once it is performed at.
/// The two pills carry the promise the rest of the flow has to keep — nothing
/// is graded, and it can be left — so both controls the design draws are here
/// and neither is a dead end.
///
/// **Aki belongs here.** She is absent from `0.5` for the same rule that puts
/// her on this screen: nobody is solving yet.
class CalibrationIntroScreen extends StatelessWidget {
  const CalibrationIntroScreen({
    super.key,
    required this.onStart,
    required this.onSkip,
  });

  /// Begins the probe.
  final VoidCallback onStart;

  /// Leaves it, with nothing answered.
  ///
  /// **Skipping is a promise this screen makes**, in the second pill. A pill
  /// that says *"Se puede saltar"* over a screen with no way out is worse than
  /// no pill.
  final VoidCallback onSkip;

  /// Slightly under `0.2`'s 200, which is the order the design draws them in
  /// (232 there against 222 here).
  ///
  /// **She was 138 for two commits, and that was a workaround.** At 160 the
  /// overflow gate reported *"A RenderFlex overflowed by 5.8 pixels"* on the
  /// notched phone at `textScaler` 1.3, and shrinking the drawing was the
  /// cheapest way to clear it. Buying a screen's fit with its artwork is a bet
  /// that the next toolchain measures type the same way, and `0.6` lost exactly
  /// that bet on CI. The body scrolls now, so the ceiling is gone and the
  /// compromise can go with it.
  static const double _akiWidth = 190;

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
          BrandButton.primary(label: 'Va, empecemos', onPressed: onStart),
          const SizedBox(height: BrandShape.space3),
          BrandButton.secondary(label: 'Saltar por ahora', onPressed: onSkip),
        ],
      ),
    );
  }

  /// Everything above the two controls, which scrolls while they do not.
  ///
  /// Same treatment and same reason as `0.6`, which cleared the overflow gate
  /// by about four percent on macOS and failed it on CI's Ubuntu. Measured here
  /// before the change: this screen overflowed at `textScaler` 1.5 against a
  /// gate at 1.3, and the Linux metrics that sank `0.6` cost roughly one
  /// twentieth of that margin. Scrolling removes the ceiling rather than moving
  /// it, and keeping the buttons **outside** the scroll view is what stops an
  /// overflow squeezing a 62px control under the 48px floor.
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
                  Center(child: Aki(width: _akiWidth, semanticLabel: 'Aki')),
                  const SizedBox(height: BrandShape.space5),
                  _title(),
                  const SizedBox(height: BrandShape.space4),
                  _promise(),
                  const SizedBox(height: BrandShape.space4),
                  _pills(),
                ],
              ),
            ),
          ),
        ),
      );

  /// The headline, in the design's two lines.
  ///
  /// `scaleDown` rather than a smaller size: at `textScaler` 1.3 on a notched
  /// phone the two lines are the widest thing on the screen, and shrinking the
  /// display face is what the rest of the app does with a numeral that will not
  /// fit.
  Widget _title() => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'UNOS RÁPIDOS PARA\nACOMODAR TU NIVEL',
          textAlign: TextAlign.center,
          style: BrandText.sectionTitle(size: 38),
        ),
      );

  Widget _promise() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            'Diez como máximo. Sirven para que los retos lleguen a tu medida, '
            'nada más.',
            textAlign: TextAlign.center,
            style: BrandText.body(),
          ),
        ),
      );

  /// The two promises, as the design's chips.
  ///
  /// Their label takes the ink rather than the eyebrow's muted default: the
  /// design sets these two in the same weight as the body they qualify.
  Widget _pills() => Wrap(
        alignment: WrapAlignment.center,
        spacing: BrandShape.space2,
        runSpacing: BrandShape.space2,
        children: <Widget>[
          for (final String promise in <String>[
            'No se califica',
            'Se puede saltar',
          ])
            CandySurface.pill(
              child: Text(
                promise,
                style: BrandText.eyebrow(color: BrandColors.ink),
              ),
            ),
        ],
      );
}
