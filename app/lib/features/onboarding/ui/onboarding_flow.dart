import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../content/model/item.dart';
import '../../../content/model/pack.dart';
import '../../../content/pack_reader.dart';
import '../../../design/widgets/spec/verdict.dart';
import '../../home/data/series_cursor_store.dart';
import '../../shell/ui/app_shell.dart';
import '../../stats/data/answer_record_store.dart';
import '../../stats/policy/local_stats.dart';
import '../policy/calibration.dart';
import 'calibration_intro_screen.dart';
import 'calibration_item_screen.dart';
import 'calibration_result_screen.dart';
import 'first_item_screen.dart';
import 'save_progress_screen.dart';
import 'welcome_screen.dart';

/// Which screen of the first run is on.
///
/// **A closed set rather than the `bool` this used to be.** Two screens fitted
/// in a flag; six do not, and a flag that selects between more than two things
/// is the shape FUN-2 exists to prevent.
enum OnboardingStep {
  /// `Bienvenida`.
  welcome,

  /// `Primer reto`.
  teachingItem,

  /// `Calibración intro`.
  calibrationIntro,

  /// `Calibración reactivo`, repeated for every item in the plan.
  probe,

  /// `Calibración resultado`. Skipped when there is nothing to report.
  result,

  /// `Guardar progreso`, the last screen of the run.
  saveProgress,
}

/// `0.2 → 0.3 → 0.4 → 0.5 ×n → 0.6 → 0.7`, and then the home.
///
/// **The whole sequence is the first run, and the flag is set at the end of
/// it.** It used to be set at the solved teaching item, which was correct when
/// `0.3` was the last screen. Four screens now sit after it and the last of
/// them is the only invitation the product ever makes to keep any of this, so a
/// flag set at `0.3` would hide them from a player who closed the app on `0.5`.
/// Leaving the teaching item still sets nothing, for the reason `FirstItemScreen`
/// records: the flag is earned by walking the run, never by escaping it.
///
/// **Two of the six screens are skipped rather than shown empty.** `0.4`–`0.6`
/// need items to ask, so a pack that could not be read steps over all three;
/// and `0.6` needs an answer to report, so a probe skipped outright steps over
/// it. Both are the reading the profile already makes about `HISTORIAL`: a
/// screen with nothing true to say is absent, not present and reading zero.
///
/// **A swap, not a push.** Every screen replaces the last, because there is
/// nothing behind any of them a player should return to. The teaching item
/// keeps its [PopScope] so the close control and the system gesture agree.
///
/// It holds no store. Whether the first run has happened is one fact with one
/// owner — `FirstRunGate` — and this widget only reports that it is over.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.onComplete,
    this.onCreateAccount,
    this.reader = const PackReader(),
    this.seriesCursor = const SeriesCursorStore(),
    this.answerRecord = const PrefsAnswerRecordStore(),
  });

  /// Called once the run is over. The caller records the flag and shows the
  /// home.
  final VoidCallback onComplete;

  /// Called by `0.7`'s green button, when a build has an account flow.
  ///
  /// Null draws no such button — a control that goes nowhere is worse than no
  /// control (DR-P2). The caller is expected to record the flag too: the player
  /// has seen the whole run either way.
  final VoidCallback? onCreateAccount;

  /// Where the probe's items come from.
  ///
  /// Injected, so a test walks the run without reaching for
  /// `assets/packs/starter.json`.
  final PackReader reader;

  /// The cursor the home reads to decide which items it has not served yet.
  ///
  /// **The probe writes to it, because the probe serves items.** It takes the
  /// pack's first ten; the home previews `pack.items.first` as `RETO DEL DÍA`
  /// and opens its first series at `seriesPlan(pack.items, from: 0)`. Without
  /// this the player would meet all ten again on the very next screen, which is
  /// the `7 + 6` defect `FirstItemScreen` records — the teaching item was the
  /// pack's first, so it was solved in the tutorial and met twice more one tap
  /// later.
  final SeriesCursorStore seriesCursor;

  /// The device's own record of answered items, which `4.1` reads as
  /// `ACIERTOS` and `PROMEDIO`.
  ///
  /// **The probe writes to it for the reason [seriesCursor] does: the probe
  /// serves real items and grades them.** Those two figures and `RETOS` are one
  /// account of the same practice, and until this existed the probe moved the
  /// third and neither of the first two — a player who answered ten probe items
  /// read `10 RETOS` beside no accuracy at all, while `LocalStats.accuracy`
  /// documents an absent figure as *"the player has answered nothing"*.
  ///
  /// **The teaching item still writes to nothing**, and by the same
  /// construction as its day log: `FirstItemScreen` builds its `RoundScreen`
  /// with no `onGraded`, so there is nothing to record into. It teaches how the
  /// app works; the probe measures how the player is doing.
  final AnswerRecordStore answerRecord;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  OnboardingStep _step = OnboardingStep.welcome;

  /// The probe, or nothing when the pack could not be read.
  List<Item> _probe = const <Item>[];

  CalibrationOutcome _outcome = CalibrationOutcome.none;

  @override
  void initState() {
    super.initState();
    _readProbe();
  }

  /// Reads the pack and plans the probe.
  ///
  /// **Called when the flow mounts, not when `0.4` is reached.** A player
  /// crosses two screens first, so the probe is ready long before it is wanted
  /// and nothing on the path has to draw a wait. There is no spinner in this
  /// app to draw one with.
  ///
  /// The `catch` is **deliberately broad, and reports rather than swallows** —
  /// the same rule `OnboardingStore` states: nothing about the stored or
  /// bundled content may prevent a launch, and that is wider than the exception
  /// hierarchy. The consequence is visible and honest: with no items, the three
  /// probe screens are skipped.
  Future<void> _readProbe() async {
    try {
      final Pack pack = await widget.reader.load();
      if (mounted) {
        setState(() => _probe = calibrationPlan(pack.items));
      }
    } catch (error) {
      debugPrint('onboarding: could not read the pack for the probe ($error)');
    }
  }

  void _to(OnboardingStep step) => setState(() => _step = step);

  /// The teaching item is behind the player.
  ///
  /// **The probe is skipped whole when there is nothing to ask**, rather than
  /// showing `0.4`'s *"Diez como máximo"* over a probe of none.
  void _afterTeachingItem() => _to(
        _probe.isEmpty
            ? OnboardingStep.saveProgress
            : OnboardingStep.calibrationIntro,
      );

  /// Remembers one probe answer the way a practice round's is remembered.
  ///
  /// **Called as each item is answered, not once at the end.** The outcome
  /// carries totals, and it deliberately carries no list of verdicts:
  /// `ProbeStrip` is built so that nothing on `0.5` can say how the player is
  /// doing, and handing `0.6` a per-item verdict would be the same leak by
  /// another door. Recording as it goes also keeps what a player answered
  /// before closing the app.
  ///
  /// Not awaited, the same as `HomeRoute`'s: a profile figure is not worth
  /// holding up the next item for, and the store already reports a write it
  /// could not make.
  void _recordAnswer(Verdict verdict, Duration elapsed) => unawaited(
        widget.answerRecord.record(
          AnsweredItem(verdict: verdict, elapsed: elapsed),
        ),
      );

  /// The probe is behind the player, and the cursor moves by **what was
  /// answered, not by what was planned**.
  ///
  /// The cursor counts items *served*, so a probe left after four advances by
  /// four and the other six are still the player's to meet. Not awaited: the
  /// home re-reads the cursor on its own launch, and a write that failed costs
  /// a repeat rather than a stuck screen.
  void _afterProbe(CalibrationOutcome outcome) {
    unawaited(widget.seriesCursor.advance(outcome.answered));
    setState(() {
      _outcome = outcome;
      _step = outcome.hasSomethingToReport
          ? OnboardingStep.result
          : OnboardingStep.saveProgress;
    });
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
        OnboardingStep.welcome => _welcome(),
        OnboardingStep.teachingItem => _teachingItem(),
        OnboardingStep.calibrationIntro => _calibrationIntro(),
        OnboardingStep.probe => _probeItem(),
        OnboardingStep.result => _calibrationResult(),
        OnboardingStep.saveProgress => _saveProgress(),
      };

  Widget _welcome() => AppShell(
        child: WelcomeScreen(onStart: () => _to(OnboardingStep.teachingItem)),
      );

  /// `0.3`, under the `PopScope` that makes the close control and the system
  /// gesture do one thing: back to the welcome.
  ///
  /// Without it they would differ — one returning, one quitting the app. Held
  /// by `test/features/onboarding/onboarding_flow_test.dart`'s *"a system back
  /// does the same thing as the close control"*.
  Widget _teachingItem() => PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) {
            _to(OnboardingStep.welcome);
          }
        },
        child: FirstItemScreen(
          onFinished: _afterTeachingItem,
          onBack: () => _to(OnboardingStep.welcome),
        ),
      );

  Widget _calibrationIntro() => AppShell(
        child: CalibrationIntroScreen(
          onStart: () => _to(OnboardingStep.probe),
          onSkip: () => _to(OnboardingStep.saveProgress),
        ),
      );

  /// `0.5`, bare like the teaching item: it brings its own `Scaffold`.
  Widget _probeItem() => CalibrationItemScreen(
        items: _probe,
        onFinished: _afterProbe,
        onGraded: _recordAnswer,
      );

  Widget _calibrationResult() => AppShell(
        child: CalibrationResultScreen(
          outcome: _outcome,
          onEnter: () => _to(OnboardingStep.saveProgress),
        ),
      );

  /// `0.7`, over the two figures the run can honestly hand it.
  ///
  /// **Challenges are the teaching item plus every probe item answered.** Both
  /// were graded on the device, so both are challenges this player did.
  ///
  /// **Days are zero, always, so the day tile is absent.** Neither the teaching
  /// item nor the probe passes a `DayLogStore`, so the home behind this screen
  /// will read no days practised, and a tile saying `1 DÍA` would be
  /// contradicted one tap later. `FirstItemScreen` records why that direction
  /// matters.
  Widget _saveProgress() => AppShell(
        child: SaveProgressScreen(
          challenges: 1 + _outcome.answered,
          days: 0,
          onCreateAccount: widget.onCreateAccount,
          onLater: widget.onComplete,
        ),
      );
}
