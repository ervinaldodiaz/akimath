import 'dart:async';

import 'package:flutter/material.dart';

import '../../../content/answer_digest.dart';
import '../../../content/model/diagnosis.dart';
import '../../../content/model/item.dart';
import '../../../design/painting/spec/dash_spec.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/icons/brand_icon.dart';
import '../../../design/widgets/candy_surface.dart';
import '../../../design/widgets/icon_button_tile.dart';
import '../../../design/widgets/keypad.dart';
import '../../../design/widgets/spec/keypad_layout.dart';
import '../../../design/widgets/spec/verdict.dart';
import '../../home/data/day_log_store.dart';
import '../policy/answer_draft.dart';
import '../policy/streak_policy.dart';
import 'stimulus/stimulus_view.dart';
import 'verdict/verdict_screen.dart';

/// The round: an item, an answer slot, a keypad, a verdict.
///
/// Everything it decides comes from `policy/` — what the typed characters
/// become is `AnswerDraft`, and whether an answer is right is `grade`. This
/// widget holds the current index and the current draft and nothing else, which
/// is what keeps all three testable without pumping a screen. Turning a prompt
/// into a node tree is `nodeForTokens`, and it lives in `policy/` for the same
/// reason the other two do.
///
/// It takes its items rather than fetching them. `HomeRoute` is the adapter
/// that reads the bundled pack and pushes this screen, so nothing here touches
/// an `AssetBundle` — and a test plays a round by handing over a one-item list.
class RoundScreen extends StatefulWidget {
  const RoundScreen({
    super.key,
    required this.items,
    this.fallbackDiagnosis,
    this.now = DateTime.now,
    this.attemptDays = const <DateTime>[],
    this.dayLog,
    this.onClose,
    this.onFinished,
    this.onAnswered,
    this.onGraded,
  });

  /// The items to play, in order. At least one.
  ///
  /// **Non-emptiness is an `initState` assert and not a constructor one.**
  /// `items.length` is not a constant expression, so a `const` constructor
  /// cannot check it. Unreachable through `RoundRoute` — `Pack.fromJson`
  /// refuses an empty pack — but this constructor is public and `required`
  /// does not mean non-empty. Unchecked, an empty list makes `_item` a
  /// `RangeError` and advancing a modulo by zero.
  final List<Item> items;

  /// What `04 Error` says when no distractor anticipated the answer, from the
  /// pack. Null for a pack that declares no misconceptions, which leaves the
  /// screen as bare as it was.
  final Diagnosis? fallbackDiagnosis;

  /// The clock, injected.
  ///
  /// Time is measured here and shown only on the verdict screen — never while
  /// an item is on screen (`req-quiet-timing`, and `CLAUDE.md`'s "no visible
  /// timer"). Taking the clock as a parameter is what lets that be tested by
  /// handing it two instants rather than by waiting.
  final DateTime Function() now;

  /// The days the player has practised, for the streak.
  final List<DateTime> attemptDays;

  /// Where today gets recorded when an answer is submitted.
  ///
  /// Optional so a test can play a round without one. When present, submitting
  /// records the day — **right or wrong**, because the streak counts days
  /// practised and not days won.
  final DayLogStore? dayLog;

  /// Leaves the series.
  ///
  /// **The only way out, and it has to exist.** A series is pushed as a
  /// full-screen route, which on iOS means no system back button and — because
  /// `fullscreenDialog` routes get no `_CupertinoBackGestureDetector` — no
  /// edge-swipe either. The round itself never ends: it cycles items forever.
  /// So without this control an iPhone player who started a series could not
  /// reach the home again without killing the app. Android hid it, because the
  /// hardware back pops the route.
  ///
  /// Defaults to `Navigator.maybePop`, so a pushed round always has an exit
  /// even if a caller forgets to wire one.
  final VoidCallback? onClose;

  /// Called instead of advancing, once the last item is behind the player.
  ///
  /// When null the round cycles — which is what a practice series does. The
  /// teaching item on `0.3` is the opposite: exactly one item, and finishing it
  /// continues the first run rather than offering another.
  ///
  /// *"Behind the player"* is not quite *"answered"*: a **one-item** round never
  /// ends on a wrong verdict, because its continue button is labelled
  /// `Intentar otro` and the only other item is this one. A multi-item round ends
  /// on its last item either way. A one-item round has no skip control at all.
  /// See `_next` for the two defects that fixed the meaning of this callback.
  ///
  /// It is handed how the round went, because the round is the only thing that
  /// knows: it graded every answer and it holds the clock. A caller that does
  /// not care ignores the argument, which is what the teaching item does.
  final void Function(RoundOutcome outcome)? onFinished;

  /// Reports every answer, right or wrong, the moment it is submitted.
  ///
  /// **Per item, not per series.** A player who abandons a series halfway has
  /// still answered what they answered, and the server should hear about it —
  /// waiting for `onFinished` would lose exactly the sittings a bus ride
  /// produces.
  ///
  /// It carries the item so the caller can read its id, which for an issued
  /// pack *is* its `(packId, index)` address. Nothing here knows what the
  /// caller does with it; `HomeRoute` journals it.
  final void Function(Item item, String answer, Duration elapsed)? onAnswered;

  /// Reports the verdict **this device decided**, and how long the item took.
  ///
  /// **Separate from [onAnswered], and that is the whole reason it exists.**
  /// That one carries what a *server* needs and deliberately no verdict: the
  /// frozen schema has nowhere to put one and the server regrades from the item
  /// it issued. This one carries what the device's own record needs. A recorder
  /// hung off `onAnswered` would have to call `gradeItem` again, which is a
  /// second decision about one answer — the exact defect `diagnose` was fixed
  /// for.
  ///
  /// **Optional, and that is how the teaching item stays out of the figures.**
  /// `Primer reto` is built without one, the same construction that keeps
  /// it out of the day log: there is nothing to record into rather than a rule
  /// somebody has to remember.
  final void Function(Verdict verdict, Duration elapsed)? onGraded;

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

/// How a round went, handed to `onFinished`.
///
/// The round is the only thing that can say: it graded every answer and it held
/// the clock. Passing it out beats a caller re-deriving it from verdicts it
/// never saw.
class RoundOutcome {
  const RoundOutcome({
    required this.correct,
    required this.total,
    required this.elapsed,
    this.outcomes = const <Verdict>[],
    this.stumble,
    this.stumbleIndex,
  });

  final int correct;
  final int total;

  /// The whole series, not the last item.
  final Duration elapsed;

  /// Every verdict, in the order the items were answered.
  ///
  /// **A count cannot draw the ring.** `2.5` shows one mark per item in series
  /// order, and `correct: 1, total: 2` cannot say which one was missed. The
  /// round is the only thing that can, because it graded them.
  ///
  /// Shorter than [total] on a series the player left part-way; the ring draws
  /// what was answered rather than padding to the length of the pack.
  final List<Verdict> outcomes;

  /// What went wrong the **first** time something did, or null.
  ///
  /// `2.5` explains one mistake. The earliest is the one that most likely
  /// caused the rest, and picking the latest would rewrite the block every time
  /// a tired player slipped again at the end.
  ///
  /// Null when the series was clean, and also when the pack declares no
  /// misconception copy — the words are the pack's, and a round given none has
  /// nothing true to say.
  final Diagnosis? stumble;

  /// Which item [stumble] came from, zero-based. Null whenever [stumble] is.
  final int? stumbleIndex;
}

class _RoundScreenState extends State<RoundScreen> {
  @override
  void initState() {
    super.initState();
    assert(
      widget.items.isNotEmpty,
      'a round needs at least one item to play',
    );
    _startedAt = widget.now();
    _roundStartedAt = _startedAt;
    _outcomes = List<Verdict?>.filled(widget.items.length, null);
    _stumbles = List<Diagnosis?>.filled(widget.items.length, null);
  }

  /// How many items were answered correctly, counted as they were graded.
  int _correct = 0;

  /// What each item's answer was judged to be, by position. Null while an item
  /// is still unanswered, which is what a series left part-way looks like.
  ///
  /// **Indexed by item, never appended per submission.** A one-item round lets
  /// a wrong answer be retried, and appending would report three outcomes for
  /// a round whose `total` is one.
  late List<Verdict?> _outcomes;

  /// The diagnosis for each item's wrong answer, by the same positions.
  late List<Diagnosis?> _stumbles;

  /// When the round itself began — not the current item. `_startedAt` is the
  /// item's; a series wants the whole span.
  late DateTime _roundStartedAt;

  int _index = 0;
  AnswerDraft _draft = AnswerDraft.empty;
  VerdictSummary? _summary;
  /// When the current item appeared.
  ///
  /// **Assigned eagerly in `initState`, never as a `late` initializer.** A
  /// `late` field with an initializer evaluates it on first *read*, and nothing
  /// reads this while the item is on screen — the first read was inside
  /// `_submit`, *after* the finish instant had been captured. Every round's
  /// first item therefore reported a negative duration, which is every first
  /// verdict a player ever sees.
  late DateTime _startedAt;

  Item get _item => widget.items[_index];

  void _onKey(KeypadKey key) {
    setState(() {
      switch (key.id) {
        case 'backspace':
          _draft = _draft.backspace();
        case 'submit':
          if (_draft.canSubmit) {
            _submit();
          }
        default:
          final String? emits = key.emits;
          if (emits != null) {
            _draft = _draft.type(emits);
          }
      }
    });
  }

  /// Judges the answer and builds what the verdict screen shows.
  ///
  /// The streak counts today as played the moment an answer is submitted —
  /// right or wrong. A wrong answer never decrements it (Q7), and it does not
  /// fail to increment it either: the streak counts days practised.
  ///
  /// **Today counts only if today was recorded.** Appending `finishedAt`
  /// unconditionally made a round with no `dayLog` — the teaching item — report
  /// `RACHA 1` on its verdict while the home behind it read `0`, because the
  /// home reads the store and the store had never been written. That is the
  /// two-screens-one-morning contradiction `StreakPolicy` was fixed for, in the
  /// other direction. The figure shown is now the figure the store will yield.
  ///
  /// **`gradeItem`, not `grade`.** An issued pack states a digest instead of an
  /// answer and the pure policy cannot compute an HMAC — see
  /// `content/answer_digest.dart`. The authored pack's items take the path they
  /// always did. That one verdict is then *handed* to `diagnoseItem` rather
  /// than recomputed, so the screen's mood and the words under it cannot
  /// disagree: one decision, made once.
  ///
  /// **The elapsed figure is wall clock, so a backgrounded app keeps counting.**
  /// What time on task *should* mean across that gap is an open product
  /// question; until it is answered, `api/time_on_task.dart` keeps the figure
  /// sendable.
  void _submit() {
    final DateTime finishedAt = widget.now();
    final DayLogStore? store = widget.dayLog;
    _recordTodayAsPractised(store, finishedAt);
    final Verdict verdict = gradeItem(_item, _draft.text);
    final Duration elapsed = finishedAt.difference(_startedAt);
    widget.onAnswered?.call(_item, _draft.text, elapsed);
    widget.onGraded?.call(verdict, elapsed);
    if (verdict == Verdict.correct) {
      _correct += 1;
    }
    final Diagnosis? fallback = widget.fallbackDiagnosis;
    final Diagnosis? diagnosis = fallback == null
        ? null
        : diagnoseItem(
            item: _item,
            typed: _draft.text,
            verdict: verdict,
            fallback: fallback,
          );
    _outcomes[_index] = verdict;
    _stumbles[_index] = diagnosis;
    _summary = VerdictSummary(
      verdict: verdict,
      diagnosis: diagnosis,
      elapsed: elapsed,
      streakDays: streakLength(
        attemptDays: <DateTime>[
          ...widget.attemptDays,
          if (store != null) finishedAt,
        ],
        today: finishedAt,
      ),
    );
  }

  /// Writes today into the day log, before the verdict is even built.
  ///
  /// Nothing about the answer reaches here, which is how the streak counts days
  /// practised rather than days won. A round built without a store — the
  /// teaching item — records nothing, and that absence is the construction that
  /// keeps it out of the figures.
  void _recordTodayAsPractised(DayLogStore? store, DateTime finishedAt) {
    unawaited(store?.record(finishedAt) ?? Future<void>.value());
  }

  /// How the series went, assembled at the moment it ends.
  ///
  /// The outcomes stop at the first unanswered item rather than padding to the
  /// length of the pack: a ring with a blank mark on it would be a claim about
  /// an item nobody saw.
  RoundOutcome _howItWent() {
    final List<Verdict> answered = <Verdict>[];
    for (final Verdict? verdict in _outcomes) {
      if (verdict == null) {
        break;
      }
      answered.add(verdict);
    }
    final int firstSlipIndex = answered.indexOf(Verdict.wrong);
    final Diagnosis? stumble =
        firstSlipIndex == -1 ? null : _stumbles[firstSlipIndex];

    return RoundOutcome(
      correct: _correct,
      total: widget.items.length,
      elapsed: widget.now().difference(_roundStartedAt),
      outcomes: List<Verdict>.unmodifiable(answered),
      stumble: stumble,
      stumbleIndex: stumble == null ? null : firstSlipIndex,
    );
  }

  /// Moves past the current item, or ends the round.
  ///
  /// **On a one-item round, a wrong verdict's continue never ends it.** `_next` is
  /// the target of every forward affordance here, and the verdict screen labels
  /// that button by correctness: `Siguiente` on a win, **`Intentar otro`** on a slip — a request
  /// for another go, not an acknowledgement. Bound to the verb rather than to the
  /// event, `onFinished` inherited it, so the child who answered *wrong* — the one
  /// who most needs the screen that teaches the answer format — was the one who
  /// permanently lost it by tapping the button the app offered them. The first run
  /// therefore completes when the item is **solved**, which is what
  /// `req-first-run` says: *"from the welcome screen to a solved item"*.
  ///
  /// **That rule belongs to a one-item round only.** On one item the only
  /// *"another one"* the button can offer is this one again. With more items it
  /// offers a genuinely different one, and the last item ends the round either
  /// way — the first version of this guard applied `solved` to every round, so a
  /// series whose last answer was wrong wrapped to item 1 and `onFinished` never
  /// fired. Nothing ships that today (`HomeRoute` passes no `onFinished`), which
  /// is exactly why it needed closing before something does.
  void _next() {
    final void Function(RoundOutcome)? finished = widget.onFinished;
    final bool isLastItem = _index == widget.items.length - 1;
    final bool retryTheOnlyItem =
        widget.items.length == 1 && _summary?.verdict != Verdict.correct;
    if (finished != null && isLastItem && !retryTheOnlyItem) {
      finished(_howItWent());
      return;
    }

    setState(() {
      _index = (_index + 1) % widget.items.length;
      _draft = AnswerDraft.empty;
      _summary = null;
      _startedAt = widget.now();
    });
  }

  /// The item, or the verdict screen once the item has been answered.
  ///
  /// **A `Scaffold` and not a bare `ColoredBox`.** Without a `Material`
  /// ancestor Flutter falls back to a `DefaultTextStyle` that paints a yellow
  /// double underline under every run of text: a debug marker that looks like a
  /// defect, and `test/design/screen_text_style_test.dart` fails on it.
  @override
  Widget build(BuildContext context) {
    final VerdictSummary? summary = _summary;
    if (summary != null) {
      return VerdictScreen(
        summary: summary,
        onContinue: _next,
        onClose: _close,
      );
    }

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
              _header(),
              const Spacer(),
              _prompt(),
              const SizedBox(height: BrandShape.space5),
              _answerSlot(),
              const Spacer(),
              Keypad(
                layout: KeypadLayout.item,
                unavailable: KeypadLayout.keysWithNoGradableAnswer,
                onKeyPressed: _onKey,
              ),
              ..._skipControl(),
            ],
          ),
        ),
      ),
    );
  }

  /// `close · progress · …` — the shell's first element, per the item-shell
  /// design. It was specified and never built, and its absence trapped an iOS
  /// player inside the session.
  void _close() {
    final VoidCallback? handler = widget.onClose;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).maybePop();
  }

  /// `Saltar este reto`, on a round that has somewhere to skip to.
  ///
  /// **A one-item round gets none, and that is not a tidiness rule.** The
  /// control routes to `_next`, which on the last item calls `onFinished` — so
  /// one tap on the teaching item's skip completed the first run permanently
  /// with nothing ever solved, past a screen whose whole job is teaching the
  /// answer format. Derived from [RoundScreen.items] rather than passed in, so
  /// a one-item round cannot be built with the control by accident.
  List<Widget> _skipControl() {
    if (widget.items.length <= 1) {
      return const <Widget>[];
    }
    return <Widget>[
      const SizedBox(height: BrandShape.space3),
      BrandButton.text(label: 'Saltar este reto', onPressed: _next),
    ];
  }

  /// `close · reto · nivel` — and deliberately no clock.
  ///
  /// Time is measured while the player solves and shown only on the verdict
  /// screen (`req-quiet-timing`, and `CLAUDE.md`'s no visible timer). The level
  /// stands where a timer would in another product.
  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        IconButtonTile(
          onPressed: _close,
          child: const BrandIcon(BrandGlyph.close, size: 22),
        ),
        Text('Reto ${_index + 1}', style: BrandText.eyebrow()),
        Text('Nivel ${_item.ladderStep}', style: BrandText.eyebrow()),
      ],
    );
  }

  /// The stimulus, drawn by whichever renderer its kind names.
  ///
  /// **Exhaustive over the sealed type**, so a seventh family is a compile
  /// error here rather than a screen that silently draws nothing. That is the
  /// whole reason `Stimulus` is sealed: `packages/contract` froze six kinds and
  /// the app ships them one at a time.
  ///
  /// The dispatch itself is [StimulusView]'s, shared with the home's preview
  /// card, and its own doc comment holds why there is only one of it.
  Widget _prompt() {
    return StimulusView(stimulus: _item.stimulus);
  }

  /// The slot the typed answer appears in.
  ///
  /// **Pink dashed throughout: a focus affordance and never a verdict**
  /// (`BrandColorRole.focus`). A judged answer leaves this screen entirely, so
  /// the slot has no verdict state to carry and never needs a second hue.
  ///
  /// **Its inner padding is two untokenised values**, set to keep a 40 px
  /// numeral clear of the 3 px outline at `textScaler` 1.3, and its width is
  /// fixed so the slot does not resize as the player types.
  ///
  /// **The figure is scaled to fit and never clipped.** At 40 px a Darumadrop
  /// `0` advances about 27 px, so 140 px holds five or six digits while
  /// [AnswerDraft.maxLength] permits twelve. Clipping the overflow meant the
  /// answer shown and the answer graded could differ — and worse, backspacing
  /// a hidden character read as a keypress that did nothing.
  ///
  /// 40 px is half the prompt's 76: the answer is read rather than solved, so
  /// it sits below the challenge in the visual hierarchy. The text carries a
  /// key so a test can read the answer back without matching a keypad key that
  /// happens to show the same digit.
  Widget _answerSlot() {
    return Row(
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
                  key: const ValueKey<String>('answer-draft'),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: BrandText.numeral(40),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
