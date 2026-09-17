import 'package:flutter/material.dart';

import '../../../content/answer_digest.dart';
import '../../../content/model/item.dart';
import '../../../design/painting/spec/dash_spec.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/candy_surface.dart';
import '../../../design/widgets/keypad.dart';
import '../../../design/widgets/spec/keypad_layout.dart';
import '../../../design/widgets/spec/verdict.dart';
import '../../home/policy/series_families.dart';
import '../../round/policy/answer_draft.dart';
import '../../round/ui/stimulus/stimulus_view.dart';
import '../policy/calibration.dart';

/// `Calibración reactivo` — one probe item, and the strip that says how
/// many are left.
///
/// **It is not the round, and composing `RoundScreen` would make it one.** That
/// screen brings its own header, its own `Scaffold` and a `VerdictScreen` after
/// every submit; a probe shows no verdict between items, because `0.4` has just
/// promised *"No se califica"* and a verdict per item is a grade per item. What
/// it does reuse is everything that decides: `AnswerDraft` for what the typed
/// characters become, `gradeItem` for whether they are right, `StimulusView`
/// for how the prompt is drawn, and `Keypad` — **never the system keyboard**.
///
/// **Aki is not on it, and the design draws her here.** `0.5`'s header carries
/// a 52px `Aki` beside the skip control, and `CLAUDE.md`'s *"nothing watches
/// you while you work"* is an invariant with a gate behind it. The invariant
/// wins; `quiet_while_you_solve_test.dart` walks this screen for exactly that.
///
/// **The strip encodes position and nothing else.** See [ProbeStrip].
class CalibrationItemScreen extends StatefulWidget {
  const CalibrationItemScreen({
    super.key,
    required this.items,
    required this.onFinished,
    this.onGraded,
    this.now = DateTime.now,
  });

  /// The probe, in the order it will be asked. `calibrationPlan` chooses them.
  final List<Item> items;

  /// The one way out, reached by answering the last item or by leaving.
  ///
  /// **One callback, two ways to reach it**, because a player who answered four
  /// of ten and left has still answered four and the result screen can say so.
  /// Which of the two happened is readable from the outcome: `answered` against
  /// `asked`.
  final void Function(CalibrationOutcome outcome) onFinished;

  /// Reports the verdict **this device decided** for one item, and how long
  /// that item took. Called once per answer, in the order they were given.
  ///
  /// **The same seam `RoundScreen.onGraded` has, and it exists here for the
  /// same reason: a probe item is practice.** Every one of them is a real pack
  /// item — `calibrationPlan` is the pack's own first ten, which is why the
  /// flow advances the series cursor past them so the home does not serve them
  /// twice — and it is graded by the same `gradeItem` the round uses. `0.7`
  /// already counts them as *"challenges this player did"*, and `4.1` divides
  /// the device's record of practice into `ACIERTOS` and `PROMEDIO`.
  ///
  /// **What this is not is a grade for the item.** `0.4` promises *"No se
  /// califica"*, and the app's own vocabulary for that word is `0.6`'s *"No es
  /// calificación. Es de dónde salimos"* — no level and no rank comes out of
  /// the probe. It is the same distinction `ProbeStrip` keeps: nothing on this
  /// screen may say how the player is doing, and this callback draws nothing.
  ///
  /// **Optional, and that is how a screen stays out of the figures.**
  /// `Primer reto` is a `RoundScreen` built without one — the tutorial teaches
  /// the app rather than measuring the player. Nothing here enforces which
  /// surface owes what; the caller decides, which is the wiring
  /// `docs/solid/shell-and-entry.md`'s finding 1 is about.
  final void Function(Verdict verdict, Duration elapsed)? onGraded;

  /// The clock, injected — measured quietly and never drawn here.
  final DateTime Function() now;

  @override
  State<CalibrationItemScreen> createState() => _CalibrationItemScreenState();
}

class _CalibrationItemScreenState extends State<CalibrationItemScreen> {
  /// Tighter vertically than the round's `space3`: this screen carries a strip
  /// and a caption the round does not, and at `textScaler` 1.3 on the notched
  /// phone the overflow gate reported 18 pixels for them.
  static const EdgeInsets _paddingThatFitsTheStripAndItsCaption =
      EdgeInsets.symmetric(
    horizontal: BrandShape.space4,
    vertical: BrandShape.space2,
  );

  /// How many items are behind the player. Also how many bars are filled.
  int _index = 0;
  int _correct = 0;
  AnswerDraft _draft = AnswerDraft.empty;

  /// When the probe began. Assigned eagerly rather than lazily, which is the
  /// defect `RoundScreen` records above the same field: a `late` initializer
  /// first read inside the submit handler measures a negative duration.
  late DateTime _startedAt;

  /// When the item now on screen appeared — not when the probe did.
  ///
  /// **The two are different questions and each has one caller.** `0.6` reports
  /// how long the whole probe took, and the answer record wants how long *an
  /// item* takes, because that is what `PROMEDIO` averages. One field answering
  /// both would report the second item as having taken as long as the first two
  /// together, and the tenth as having taken the whole probe.
  late DateTime _itemStartedAt;

  @override
  void initState() {
    super.initState();
    assert(widget.items.isNotEmpty, 'a probe needs at least one item to ask');
    _startedAt = widget.now();
    _itemStartedAt = _startedAt;
  }

  Item get _item => widget.items[_index];

  void _onKey(KeypadKey key) {
    if (key.id == 'submit') {
      if (_draft.canSubmit) {
        _submit();
      }
      return;
    }
    setState(() {
      if (key.id == 'backspace') {
        _draft = _draft.backspace();
      } else {
        final String? emits = key.emits;
        if (emits != null) {
          _draft = _draft.type(emits);
        }
      }
    });
  }

  /// Grades the answer, reports it, and moves on without showing a verdict.
  ///
  /// **The last answer does not advance the index.** Reporting is the caller's
  /// cue to replace this screen, and an index one past the end would be a
  /// `RangeError` in whatever frame ran first.
  ///
  /// **[CalibrationItemScreen.onGraded] fires before the early return that ends
  /// the probe.** Ending the probe is not a reason to drop the answer that
  /// ended it.
  void _submit() {
    final DateTime finishedAt = widget.now();
    final Verdict verdict = gradeItem(_item, _draft.text);
    if (verdict == Verdict.correct) {
      _correct += 1;
    }
    widget.onGraded?.call(verdict, finishedAt.difference(_itemStartedAt));
    if (_index == widget.items.length - 1) {
      _report(answered: widget.items.length, at: finishedAt);
      return;
    }
    setState(() {
      _index += 1;
      _draft = AnswerDraft.empty;
      _itemStartedAt = finishedAt;
    });
  }

  /// Leaves the probe with whatever has been answered so far.
  void _leave() => _report(answered: _index, at: widget.now());

  void _report({required int answered, required DateTime at}) =>
      widget.onFinished(
        CalibrationOutcome(
          asked: widget.items.length,
          answered: answered,
          correct: _correct,
          elapsed: at.difference(_startedAt),
        ),
      );

  /// The screen, under a `PopScope` that makes **a system back mean what
  /// `Saltar` means** — the same agreement the teaching item's `PopScope`
  /// makes. The probe is swapped in rather than pushed, so without it an
  /// Android back would quit the app from the middle of the first run.
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _leave();
        }
      },
      child: _screen(),
    );
  }

  /// Everything the player sees, on a `Scaffold`.
  ///
  /// A `Scaffold` rather than a bare `ColoredBox`, for the same reason the
  /// round has one: without a Material ancestor every run of text gets
  /// Flutter's yellow debug underline, and `screen_text_style_test.dart` fails
  /// on it.
  Widget _screen() {
    return Scaffold(
      backgroundColor: BrandColors.cream,
      body: SafeArea(
        child: Padding(
          padding: _paddingThatFitsTheStripAndItsCaption,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(),
              const SizedBox(height: BrandShape.space2),
              ProbeStrip(
                heights: probeBarHeights(widget.items.length),
                done: _index,
              ),
              const SizedBox(height: BrandShape.space1),
              Text(
                'Las alturas cambian: no es una serie, es una sonda',
                style: BrandText.caption(),
              ),
              const Spacer(),
              Text(
                familyLabel(_item.stimulus).toUpperCase(),
                textAlign: TextAlign.center,
                style: BrandText.eyebrow(),
              ),
              const SizedBox(height: BrandShape.space3),
              StimulusView(stimulus: _item.stimulus),
              const SizedBox(height: BrandShape.space3),
              _answerSlot(),
              const Spacer(),
              Keypad(
                layout: KeypadLayout.item,
                unavailable: KeypadLayout.keysWithNoGradableAnswer,
                onKeyPressed: _onKey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `TE ESTOY CONOCIENDO · 4 DE 10`, and the way out.
  ///
  /// **The count, not a clock.** Nothing on a solving surface may read as one
  /// (`quiet_while_you_solve_test.dart`), and *"how many are left"* is the one
  /// number that tells a player where they are without timing them.
  ///
  /// The count is set in the accent, which is what the design sets this line
  /// in. It is not a verdict colour and could not be: `BrandColorRole` has no
  /// arm that would let it be one here.
  Widget _header() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Flexible(
            child: Text(
              'TE ESTOY CONOCIENDO · ${_index + 1} DE ${widget.items.length}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: BrandText.eyebrow(
                color: BrandColorRole.accent.color,
                size: 11,
              ),
            ),
          ),
          BrandButton.text(label: 'Saltar', onPressed: _leave),
        ],
      );

  /// Where the typed answer shows, in the round's own treatment.
  ///
  /// **A near-copy of `RoundScreen._answerSlot`, deliberately and temporarily.**
  /// The shared thing wants to be a widget under `design/widgets/`, which this
  /// change was scoped out of touching. Extracting it is the follow-up, and
  /// until it happens the two are one review away from drifting.
  ///
  /// **Pink dashed: a focus affordance, never a verdict.** A probe has no
  /// verdict state at all, which makes that easy to keep true here.
  Widget _answerSlot() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CandySurface(
            borderDash: DashSpec.locked,
            borderColor: BrandColorRole.focus.color,
            borderWidth: BrandShape.borderWidth,
            borderRadius: BrandShape.radiusSlot,
            shadowOffset: Offset.zero,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SizedBox(
              width: 140,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _draft.text.isEmpty ? ' ' : _draft.text,
                    key: const ValueKey<String>('probe-answer-draft'),
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: BrandText.numeral(34),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

/// The bars over `0.5`, one per item the probe will ask.
///
/// **It takes a count, never a list of verdicts, and that is the design.** The
/// strip says *where you are*; every filled bar is the same accent and the
/// heights are fixed before the first answer, so nothing on it can leak how the
/// player is doing. A green-for-right bar would break `0.4`'s *"No se
/// califica"* and BRD-1's shape-not-hue rule in one stroke, and it is exactly
/// the improvement somebody adds later — hence a type that cannot express it.
class ProbeStrip extends StatelessWidget {
  const ProbeStrip({super.key, required this.heights, required this.done});

  /// One height per item, from `probeBarHeights`.
  final List<double> heights;

  /// How many bars are behind the player.
  final int done;

  /// The tallest bar, which is the row's own height so the short ones can sit
  /// on its baseline. No token: this is the design's own figure for a strip
  /// nothing else in the app draws.
  static const double _rowHeight = 22;

  /// A radius small enough not to round a 14px bar into a lozenge.
  /// `BrandShape.radiusSlot` is 12 and does exactly that.
  static const double _barRadius = 5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int index = 0; index < heights.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(width: BrandShape.space1),
            Expanded(child: _bar(heights[index], filled: index < done)),
          ],
        ],
      ),
    );
  }

  Widget _bar(double height, {required bool filled}) => Container(
        height: height,
        decoration: BoxDecoration(
          color: filled ? BrandColorRole.accent.color : BrandColors.surface,
          borderRadius: BorderRadius.circular(_barRadius),
          border: Border.all(
            color: BrandColors.ink,
            width: BrandShape.borderWidthSmallSurface,
          ),
        ),
      );
}
