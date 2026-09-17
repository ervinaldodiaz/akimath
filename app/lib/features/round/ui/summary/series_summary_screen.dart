import 'package:flutter/material.dart';

import '../../../../content/model/diagnosis.dart';
import '../../../../design/brand/aki.dart';
import '../../../../design/math/spec/es_mx_number.dart';
import '../../../../design/tokens/tokens.dart';
import '../../../../design/widgets/brand_button.dart';
import '../../../../design/widgets/candy_surface.dart';
import '../../../../design/widgets/spec/verdict.dart';
import '../../../../design/widgets/speech_bubble.dart';
import '../../../../design/widgets/stat_tile.dart';
import '../../../../design/widgets/verdict_ring.dart';

/// How a finished series went.
///
/// **Every figure on it is measured.** The round graded each item and held the
/// clock, so the per-item outcomes, the total time and the streak are facts it
/// hands over, and there is nothing else. Three things the design draws are
/// deliberately absent — see [SeriesSummaryScreen].
class SeriesResult {
  const SeriesResult({
    required this.correct,
    required this.total,
    required this.elapsed,
    required this.streakDays,
    this.outcomes = const <Verdict>[],
    this.stumble,
    this.stumbleIndex,
  });

  final int correct;
  final int total;

  /// Measured quietly across the whole series (`req-quiet-timing`).
  final Duration elapsed;

  /// A local calendar fact, from `StreakPolicy`.
  final int streakDays;

  /// Every verdict, in the order the items were answered, from `RoundOutcome`.
  ///
  /// **Defaulted to empty because a caller may not have it yet**, and the
  /// screen states the score in words when it does not — an empty ring row
  /// would read as a clean sheet, which is the one wrong thing it could say.
  final List<Verdict> outcomes;

  /// The pack's words for the first slip, or null.
  ///
  /// Null on a clean series, and null when the pack declares no misconception
  /// copy. The block is absent either way: a heading over nothing is the thing
  /// `HISTORIAL` does not do on `4.1`.
  final Diagnosis? stumble;

  /// Which item [stumble] came from, zero-based, from `RoundOutcome`.
  ///
  /// The design's copy names it — *"usaste diferencia constante en el cuarto
  /// reto"* — and a player reading advice about a mistake needs to know which
  /// of five it was about. Null leaves the card unnumbered rather than guessing.
  final int? stumbleIndex;
}

/// `Resumen de serie` — the screen that makes a series a thing you finish.
///
/// Before this existed the round wrapped modulo its item list and played
/// forever, which is an exercise rather than a game.
///
/// **Aki is here, and the design is not why.** `2.5` draws no dog; the corpus
/// rule is that she never appears while the learner is *solving*, and
/// `quiet_while_you_solve_test.dart` names this screen among the three she must
/// be on. A summary is not a solve. The design departure is deliberate and the
/// committed test is the reason.
///
/// **Three of the design's blocks are absent, and each for the same reason.**
/// `2.5` draws a `+12 RATING` tile, a `QUÉ MEJORÓ` pair of mastery bars and a
/// `QUÉ SIGUE · UNA SOLA COSA` recommendation. Nothing produces any of them:
/// rating never runs in Dart and `GET /me/standing` answers one *per skill*,
/// nothing tracks mastery per skill at all — the device never sees a
/// `skill_id` — and a recommendation needs `GET /items/next`, which answers
/// 501. They were drawn from invented constants until 2026-09-02, when two
/// structurally different series printed the byte-identical `+ 12 RATING` and
/// `Fracciones 68 % · Multiplicar 96 %` in front of a real player, neither
/// having contained a fraction or a multiplication. **Absent, not zeroed and
/// not greyed out** (DR-P2), the same reading `HISTORIAL` takes on `4.1`;
/// `only_what_it_can_prove_test.dart` is what keeps them absent until
/// something computes them.
///
/// **It scrolls, and it still needs to with three blocks gone.** The design
/// lays five out in a fixed flex column that happens to fit at `textScaler`
/// 1.0 and does not at 1.3, and the overflow gate checks both. Removing the
/// invented three took the fixed part of the column well under the fold — but
/// the block that remains is the one with no ceiling: `QUÉ SE TORCIÓ` renders
/// the pack's own prose, as many steps as a `Diagnosis` carries, so the height
/// is content the screen does not control. The button stays outside the scroll
/// view so the way out is never below the fold.
class SeriesSummaryScreen extends StatelessWidget {
  const SeriesSummaryScreen({
    super.key,
    required this.result,
    required this.onDone,
  });

  final SeriesResult result;
  final VoidCallback onDone;

  static const double _akiWidth = 120;

  /// The mark for one answered item.
  ///
  /// 22 and not the design's 18: `VerdictRing.defaultSize`'s own comment
  /// anticipates *"the strip passes 22 when it lands"*, and the glyph inside it
  /// — which is what makes the mark readable without hue — needs the room
  /// (BRD-2c).
  static const double _markSize = 22;

  /// What Aki says, which is a function of the score and never of the failure.
  ///
  /// Four bands rather than one sentence: a fixed line would pass every copy
  /// assertion and tell a player who got none the same thing as a player who got
  /// all five. None of them names a mistake — `req-diagnosis-copy` is about the
  /// product, not about the verdict screen.
  String get _line {
    if (result.total == 0) return 'Listo.';
    if (result.correct == result.total) return '¡Todas! Qué manera de cerrar.';
    if (result.correct == 0) return 'Ya está la serie. La próxima cae otra.';
    if (result.correct * 2 >= result.total) return 'Buena serie. Vas bien.';
    return 'Serie terminada. Poco a poco.';
  }

  /// The scrolling body, and the one button under it.
  ///
  /// **A `Scaffold` and not a bare `ColoredBox`.** Without a `Material`
  /// ancestor Flutter paints a yellow debug underline under every run of text,
  /// which looks like a defect and which
  /// `test/design/screen_text_style_test.dart` fails on.
  ///
  /// **One button, and no `Ver el reto que falló`.** The design draws a second
  /// one; nothing reviews a past item, so it would be a control that does
  /// nothing. Absent rather than dead (DR-P2).
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.cream,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: _scrollingBody()),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BrandShape.space4,
                BrandShape.space2,
                BrandShape.space4,
                BrandShape.space3,
              ),
              child: BrandButton.primary(
                label: 'Volver al inicio',
                onPressed: onDone,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrollingBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: BrandShape.space4,
        vertical: BrandShape.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Aki(
              width: _akiWidth,
              pose: AkiPose.correct,
              semanticLabel: 'Aki',
            ),
          ),
          const SizedBox(height: BrandShape.space2),
          Center(child: SpeechBubble(text: _line, maxWidth: 280)),
          const SizedBox(height: BrandShape.space4),
          _headline(),
          const SizedBox(height: BrandShape.space3),
          _tiles(),
          ..._whatWentWrong(),
        ],
      ),
    );
  }

  /// `SERIE COMPLETA`, and the ring of per-item outcomes under it.
  ///
  /// The design puts them on one row. Five marks and a 40 px display face do not
  /// share 350 px, and at `textScaler` 1.3 they share less — so the ring gets
  /// its own row and keeps the mark size the glyph needs.
  Widget _headline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('SERIE COMPLETA', style: BrandText.sectionTitle(size: 28)),
        const SizedBox(height: BrandShape.space2),
        _score(),
      ],
    );
  }

  /// The ring, or the count in words when the outcomes are not known.
  ///
  /// **Never nothing.** A caller that hands over no outcomes still played a
  /// series, and an empty row where the marks go reads as a clean sheet.
  Widget _score() {
    if (result.outcomes.isEmpty) {
      return Text(
        '${result.correct} de ${result.total}',
        style: BrandText.numeral(24),
      );
    }
    return Wrap(
      spacing: BrandShape.space1,
      runSpacing: BrandShape.space1,
      children: <Widget>[
        for (final Verdict outcome in result.outcomes)
          VerdictRing(outcome, size: _markSize),
      ],
    );
  }

  /// Two tiles: the time and the streak.
  ///
  /// **The design draws three and the third was the rating.** It is gone rather
  /// than blank — the same pair `03 Acierto` and `04 Error` already show, and
  /// for the same recorded reason: nothing here may be a figure a later sync
  /// could contradict.
  ///
  /// **`RACHA` and not the design's `DÍAS`.** `4.1` already labels *days
  /// practised* `DÍAS`, and that is a different figure from a streak; one word
  /// for two facts teaches a reader the wrong one.
  ///
  /// **Each figure scales down inside its tile.** Three natural-width tiles
  /// overflowed 390 px by 98, and `FittedBox` keeps a long figure inside its own
  /// tile rather than pushing the next one off the edge — which is what has to
  /// hold at `textScaler` 1.3. Two have more room than three had, and the
  /// wrapping stays: an hour-long series is still the widest figure a tile here
  /// can hold.
  Widget _tiles() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _tile(
            'EN TOTAL',
            EsMxNumber.seconds(result.elapsed.inMilliseconds / 1000, places: 1),
          ),
        ),
        const SizedBox(width: BrandShape.space2),
        Expanded(child: _tile('RACHA', EsMxNumber.integer(result.streakDays))),
      ],
    );
  }

  Widget _tile(String label, String figure) {
    return StatTile(
      label: label,
      value: FittedBox(
        fit: BoxFit.scaleDown,
        child: StatValue(figure, size: StatTileVariant.compact.valueSize),
      ),
      variant: StatTileVariant.compact,
    );
  }

  /// `QUÉ SE TORCIÓ` — the pack's own words for the first slip, or nothing.
  ///
  /// Returns a list so the gap above it disappears with it; a `SizedBox` left
  /// behind is a paragraph of blank cream nobody can explain.
  ///
  /// The heading is set in ink rather than the eyebrow's default muted: `4.1`'s
  /// muted eyebrow sits on white, and the design sets this one on ink because
  /// the card is coral. The item is numbered from one, because a player counts
  /// from one.
  List<Widget> _whatWentWrong() {
    final Diagnosis? stumble = result.stumble;
    if (stumble == null) {
      return const <Widget>[];
    }
    final int? at = result.stumbleIndex;
    return <Widget>[
      const SizedBox(height: BrandShape.space3),
      CandySurface(
        background: BrandColorRole.error.color,
        borderRadius: BrandShape.radiusCard,
        padding: const EdgeInsets.all(BrandShape.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'QUÉ SE TORCIÓ',
                    style: BrandText.eyebrow(color: BrandColors.ink),
                  ),
                ),
                if (at != null)
                  Text('Reto ${at + 1}', style: BrandText.eyebrow(color: BrandColors.ink)),
              ],
            ),
            for (final String step in stumble.steps) ...<Widget>[
              const SizedBox(height: BrandShape.space2),
              Text(step, style: BrandText.body()),
            ],
          ],
        ),
      ),
    ];
  }
}
