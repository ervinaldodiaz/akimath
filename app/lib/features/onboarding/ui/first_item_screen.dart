import 'package:flutter/widgets.dart';

import '../../../content/model/item.dart';
import '../../round/ui/round_screen.dart';

/// `Primer reto` — the item that teaches how an answer is typed.
///
/// It is the round, with one item and a different ending: answering it continues
/// the first run rather than offering another. That is why it composes
/// `RoundScreen` instead of reimplementing it — a second solve screen would be a
/// second place to keep the keypad, the answer slot and the verdict in agreement.
///
/// **Aki is absent**, because the learner is solving. She is on `0.2` for the
/// same rule.
///
/// **The teaching item records nothing and reports nothing**, and that has to
/// be true of the number on screen as well as of the number in storage. Say
/// *the teaching item* rather than *the first run*: the four screens after this
/// one do record, the probe among them, and a sentence scoped to the container
/// went stale the day they landed (CMT-2a).
///
/// Three absent arguments are the whole mechanism, and nothing in the built
/// `RoundScreen` shows a reader that they are missing:
///
/// - no `dayLog`, so submitting writes no day;
/// - no `attemptDays`, and `RoundScreen` counts only the day it actually
///   recorded, so the verdict reads `RACHA 0` — which is what the home behind
///   it reads. It read `RACHA 1` first: a streak claimed on a player's very
///   first result and contradicted one tap later;
/// - no `onGraded`, so the answer reaches neither `ACIERTOS` nor `PROMEDIO`.
///   The probe passes one, because a probe item is a real pack item and a
///   tutorial item is not.
///
/// The `RoundOutcome` the round hands back is discarded for the same reason:
/// one item, and nothing counts it.
class FirstItemScreen extends StatelessWidget {
  const FirstItemScreen({
    super.key,
    required this.onFinished,
    required this.onBack,
  });

  /// Called when the teaching item has been answered and acknowledged.
  ///
  /// **The only path past the teaching item**, and nothing further: the run
  /// itself is completed four screens later, on `0.7`. This doc said *"the only
  /// path that completes the first run"* while `0.3` was the last screen, and
  /// `onboarding_flow_test.dart`'s *"and nothing before 0.7 records it"* is
  /// what holds the corrected claim.
  final VoidCallback onFinished;

  /// Called by the close control.
  ///
  /// **Leaving is not finishing.** Routing the close here rather than to
  /// [onFinished] means a mistaken tap costs a few seconds instead of skipping
  /// the only screen that teaches the answer format — the teaching item is
  /// passed by answering, not by escaping. And it is not a trap either: the
  /// welcome behind it is not a solve screen and carries the action that comes
  /// back.
  final VoidCallback onBack;

  /// The teaching item.
  ///
  /// Fixed rather than fetched: a tutorial that varied between installs would be
  /// a tutorial nobody could support, and drawing it from the pack would tempt
  /// someone to rate it. Single-digit operands keep the tutorial about the
  /// keypad rather than about the arithmetic, and a two-digit answer is the
  /// point — it is what teaches that digits accumulate and that backspace takes
  /// one away.
  ///
  /// **It must not be an item the starter pack holds.** It was `7 + 6`, which is
  /// `add-1` — the pack's *first* item, so it is what the home previews as
  /// `RETO DEL DÍA` and what `Empezar la serie` opens with. A new player solved
  /// it in the tutorial and then met it twice more on the next screen. Nothing in
  /// the suite could see that: the tests hand this screen its item and the home
  /// tests hand the home a fixture. Two launches on a simulator showed it at once.
  static const Item teachingItem = Item(
    id: 'teaching',
    stimulus: ArithmeticStimulus(<PromptToken>[
      PromptToken.text('5'),
      PromptToken.operator('+'),
      PromptToken.text('8'),
      PromptToken.operator('='),
    ]),
    answer: PlainAnswer('13'),
    ladderStep: 1,
  );

  @override
  Widget build(BuildContext context) {
    return RoundScreen(
      items: const <Item>[teachingItem],
      onFinished: (_) => onFinished(),
      onClose: onBack,
    );
  }
}
