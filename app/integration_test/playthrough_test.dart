/// The whole app, driven on a real device.
///
/// **This is what a written observation was standing in for.** Every widget test
/// in `test/` pumps a screen in isolation with a fake bundle and a fake store;
/// this runs `main()` on an actual simulator, against the real asset bundle, the
/// real `shared_preferences` plugin and the real renderer, and taps its way from
/// a fresh install to a finished series.
///
/// **And the fresh install is now made rather than assumed.** The case below is
/// named for one, and until `launchOnAFreshInstall` existed it produced none:
/// the first-run walk sat behind `if (WelcomeScreen … isNotEmpty)` on a handset
/// carrying the completed flag, so those assertions never ran. The six-family
/// claim at the end depended on the same thing without saying so —
/// `seriesPlan` starts at `akimath.items_served.v1`, so ten items cover six
/// families only from a cursor of zero, and on a device mid-pack this would
/// have failed as if the pack had lost a family.
///
/// **Two series, not one, and the reason is coverage.** The pack is interleaved
/// so all six families appear inside the first ten items — `pack_variety_test`
/// asserts that against the file — and this is where that claim is cashed on a
/// real device: every family drawn by the real renderer, its answer typed on
/// the app's own keypad, and graded.
///
/// It is also the thing `docs/decisions/OPEN.md` §7 said was missing: a press
/// that a machine can perform. Two `f0-*` Tier 2 tasks were open on exactly
/// that.
library;

import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/design/widgets/verdict_ring.dart';
import 'package:akimath_app/features/home/ui/home_screen.dart';
import 'package:akimath_app/features/round/ui/round_screen.dart';
import 'package:akimath_app/features/round/ui/summary/series_summary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/launch.dart';

/// The answer the item on screen is asking for, read off the prompt.
///
/// Typed rather than looked up, because the pack is real content and this test
/// should not carry a second copy of it.
Item _currentItem(WidgetTester tester) {
  final RoundScreen round = tester.widget<RoundScreen>(find.byType(RoundScreen));
  final int index = int.parse(
    (tester.widget<Text>(find.textContaining('Reto ')).data ?? 'Reto 1')
        .replaceAll(RegExp(r'\D'), ''),
  );
  return round.items[index - 1];
}

String _expectedAnswer(WidgetTester tester) => _currentItem(tester).expected;

/// What kind of question the item on screen is asking.
///
/// Read off the live `RoundScreen`, so it names what the device actually drew
/// rather than what the pack was expected to contain.
String _currentFamily(WidgetTester tester) =>
    switch (_currentItem(tester).stimulus) {
      ArithmeticStimulus() => 'arithmetic',
      NumberSeriesStimulus() => 'numberSeries',
      MatrixStimulus() => 'matrix',
      AnalogyStimulus() => 'analogy',
      HiddenOperationStimulus() => 'hiddenOperation',
      FigurateStimulus() => 'figurate',
    };

/// A character of an answer, mapped to the key that produces it.
///
/// The pack's answers are real content, so `-7` and `5/4` both occur and both
/// have to be typeable. The minus is `negate` and the fraction bar is
/// `fraction`, neither of which is the character on the key face.
const Map<String, String> _keyFor = <String, String>{
  '-': 'negate',
  '\u2212': 'negate',
  '/': 'fraction',
};

/// Opens a series from the home and waits for the round to draw.
///
/// **Scrolled to first.** The home is taller than the viewport and
/// `Empezar la serie` sits below the fold: `tap` on an off-screen widget hits
/// the coordinates it *would* occupy, the hit test misses, and the failure
/// reads as "the series never opened" rather than "the button was not visible".
///
/// **And budgeted, like the home.** The series reads the bundled pack through
/// the real asset bundle, which `pumpAndSettle` can return before.
Future<void> _startTheSeries(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Empezar la serie'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Empezar la serie'));
  for (int i = 0; i < 20 && find.byType(RoundScreen).evaluate().isEmpty; i++) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }
  expect(find.byType(RoundScreen), findsOneWidget,
      reason: 'the series never opened');
}

Future<String> _answerCurrentItem(WidgetTester tester) async {
  final String family = _currentFamily(tester);
  for (final String character in _expectedAnswer(tester).split('')) {
    await pressKey(tester, _keyFor[character] ?? character);
  }
  await pressKey(tester, 'submit');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Siguiente'));
  await tester.pumpAndSettle();
  return family;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a fresh install plays through two finished series, which is '
      'what covers all six families', (WidgetTester tester) async {
    await launchOnAFreshInstall(tester);

    await _startTheSeries(tester);

    final Set<String> answered = <String>{};

    for (int series = 0; series < 2; series++) {
      if (series > 0) {
        await _startTheSeries(tester);
      }
      expect(find.byType(RoundScreen), findsOneWidget);

      for (int i = 0; i < 5; i++) {
        if (find.byType(SeriesSummaryScreen).evaluate().isNotEmpty) break;
        answered.add(await _answerCurrentItem(tester));
      }

      expect(find.byType(SeriesSummaryScreen), findsOneWidget,
          reason: 'series ${series + 1} did not end');
      expect(
        tester.widgetList<VerdictRing>(find.byType(VerdictRing)),
        hasLength(5),
        reason: 'the ring on a real device, not `5 de 5`: the words are the '
            'summary\'s fallback for a caller handing over no outcomes, and '
            'the route hands over the round\'s, so five items answered are '
            'five marks. This is what caught the wiring being absent on the '
            'simulator while every widget test was green.',
      );

      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    }

    expect(
      answered,
      hasLength(6),
      reason: 'ten items on a real device covered only $answered',
    );
  });
}
