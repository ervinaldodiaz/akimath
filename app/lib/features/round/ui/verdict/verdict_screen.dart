import 'package:flutter/material.dart';

import '../../../../content/model/diagnosis.dart';
import '../../../../design/brand/aki.dart';
import '../../../../design/icons/brand_icon.dart';
import '../../../../design/math/spec/es_mx_number.dart';
import '../../../../design/tokens/tokens.dart';
import '../../../../design/widgets/brand_button.dart';
import '../../../../design/widgets/icon_button_tile.dart';
import '../../../../design/widgets/spec/verdict.dart';
import '../../../../design/widgets/spec/verdict_copy.dart';
import '../../../../design/widgets/stat_tile.dart';
import '../../../../design/widgets/verdict_ring.dart';

/// What a verdict screen is told. Two numbers and a result — nothing else.
///
/// **No rating, and no placeholder for one** (Q3, decided 2026-08-15). F2 has
/// no server and the rating is the server's exclusive authority (D17), so a
/// verdict screen in F2 carries **no number that sync can later contradict**.
/// The rating tile and the delta come back with `f3-attempt-sync`; this is a
/// subtraction with a named return phase, not a redesign.
class VerdictSummary {
  const VerdictSummary({
    required this.verdict,
    required this.elapsed,
    required this.streakDays,
    this.diagnosis,
  });

  final Verdict verdict;

  /// Measured quietly while solving and shown only here (`req-quiet-timing`).
  final Duration elapsed;

  /// A local calendar fact, from `StreakPolicy`.
  final int streakDays;

  /// What to say about *this* wrong answer, from `diagnose`.
  ///
  /// Null on a correct answer, and null for a pack that declares no
  /// misconceptions — which is every pack written before they existed, and
  /// which leaves the screen exactly as it was.
  final Diagnosis? diagnosis;
}

/// `03 Acierto` and `04 Error`, which are one screen with two moods.
///
/// **The copy never names the failure.** No "incorrecto", "error", "fallaste"
/// or "mal" appears on either mood — `req-diagnosis-copy`, asserted by a test
/// that scans the rendered tree. Aki's `slip` pose stoops a little and never
/// looks disappointed, and the tail curl growing back in green is the whole of
/// what a wrong answer costs.
///
/// The verdict itself is carried by `VerdictRing`: shape and glyph first, hue
/// second, so it survives a reader who cannot separate green from coral. That
/// is BRD-1 — deuteranopia collapses `#5ED6A4` and `#FF8A5B`, so `Verdict`
/// carries an outline and a glyph and no colour at all, and this screen has to
/// reach for a shape because a shape is all there is.
/// `test/architecture/verdict_is_not_a_colour_test.dart` is the gate.
class VerdictScreen extends StatelessWidget {
  const VerdictScreen({
    super.key,
    required this.summary,
    required this.onContinue,
    required this.onClose,
  });

  final VerdictSummary summary;
  final VoidCallback onContinue;

  /// Leaves the series. A verdict is a full screen with no system back on iOS,
  /// so it carries the same exit the item does.
  final VoidCallback onClose;

  bool get _correct => summary.verdict == Verdict.correct;

  /// Aki's art is 182 px inside a 156 px band — **26 px of deliberate upward
  /// overflow** on the error screen. In CSS it paints over; a fixed-height
  /// `Column` child in Flutter clips or throws, so the band is a `Stack` with
  /// the art aligned to its bottom and allowed to exceed it.
  static const double _bandHeight = 156;
  static const double _akiWidth = 182;

  /// Aki, the ring, the headline, the diagnosis and the two tiles.
  ///
  /// **The middle scrolls and the button does not.** Four steps of diagnosis at
  /// `textScaler` 1.3 overflow by 78 px, and shrinking the copy until it fits
  /// would make the screen worse for exactly the readers who chose large text —
  /// the home's design D2, in the one other place the argument applies. The
  /// middle stays centred when there is room, so the common case looks as it
  /// did, and the button sits last so nothing is below the thing the screen is
  /// asking for.
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
              Align(
                alignment: Alignment.centerLeft,
                child: IconButtonTile(
                  onPressed: onClose,
                  child: const BrandIcon(BrandGlyph.close, size: 22),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _band(),
                            const SizedBox(height: BrandShape.space4),
                            VerdictRing(summary.verdict),
                            const SizedBox(height: BrandShape.space3),
                            _headline(),
                            if (_steps.isNotEmpty) ...<Widget>[
                              const SizedBox(height: BrandShape.space3),
                              _stepList(),
                            ],
                            const SizedBox(height: BrandShape.space5),
                            _tiles(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: BrandShape.space3),
              BrandButton.primary(
                label: _correct ? 'Siguiente' : 'Intentar otro',
                onPressed: onContinue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The one line that names the mood, from `verdict_copy.dart`.
  ///
  /// That file is the one place the two headlines live — `4.5`'s legend reads
  /// the same strings, so the key cannot teach a word this screen does not say.
  ///
  /// The wrong case lost its second sentence, *"Mira cómo va."*: the diagnosis
  /// steps below now say exactly that, concretely, instead of promising it.
  Widget _headline() => Text(
        verdictHeadline(summary.verdict),
        style: BrandText.cardTitle(size: 22),
      );

  /// The steps to show, if any. A correct answer never has them.
  List<String> get _steps =>
      _correct ? const <String>[] : (summary.diagnosis?.steps ?? const <String>[]);

  /// **The steps, not the paragraph** (design D4). `explain` says the same
  /// thing at length, and a screen printing both asks a player to read it
  /// twice.
  Widget _stepList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final String step in _steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('· $step', style: BrandText.caption()),
          ),
      ],
    );
  }

  Widget _band() {
    return SizedBox(
      height: _bandHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          Aki(
            width: _akiWidth,
            pose: _correct ? AkiPose.correct : AkiPose.slip,
            semanticLabel: _correct ? 'Aki celebrando' : 'Aki intentando otra vez',
          ),
        ],
      ),
    );
  }

  /// **Two tiles, not three.** Time and streak. Q4 moved the rating delta to
  /// the series and Q3 hid the rating outright in F2.
  Widget _tiles() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        StatTile(
          label: 'TIEMPO',
          value: StatValue(
            EsMxNumber.seconds(summary.elapsed.inMilliseconds / 1000, places: 1),
            size: _variant.valueSize,
          ),
          variant: _variant,
        ),
        const SizedBox(width: BrandShape.space3),
        StatTile(
          label: 'RACHA',
          value: StatValue(
            EsMxNumber.integer(summary.streakDays),
            size: _variant.valueSize,
          ),
          variant: _variant,
        ),
      ],
    );
  }

  /// `03` draws raised tiles; `04` draws flat ones.
  StatTileVariant get _variant =>
      _correct ? StatTileVariant.raised : StatTileVariant.flat;
}
