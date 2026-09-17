import 'package:akimath_app/design/tokens/tokens.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/design/widgets/pressable_surface.dart';
import 'package:akimath_app/features/round/ui/round_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/launch.dart';

/// A key travels into its own shadow — **in the app that ships**.
///
/// `pressable_surface_test.dart` has asserted this since F0 and
/// `f0-pressable-surface` 5.3 and `f0-keypad` 3.3 both left their Tier 2 open
/// anyway, for a reason worth keeping: a synthetic `PointerDownEvent` drove the
/// pressed state under `flutter test` and **did nothing in the device build**,
/// with nothing on the console to say why. Three attempts, then stopped, and
/// the tasks were written down as blocked on tooling rather than ticked.
///
/// The tooling is `integration_test`, which was named as one of the two things
/// that would close them. It drives the real app on the device through the same
/// `WidgetTester`, so a press here is a press in the build a player installs.
///
/// **What this closes and what it does not.** It answers *does the travel
/// happen on the device* — measured, in logical pixels, off the painted
/// decoration. It does not answer *does it read as sinking rather than
/// sliding*, which is a human judgement and stays a human's.
///
/// **One pad, chosen, not two discovered.** This helper used to branch on
/// whichever screen the handset opened: a welcome meant the teaching item's pad
/// and anything else meant the round's, so which keypad the measurement came
/// off was a property of the simulator rather than of the test. It asks for a
/// returning player now and always measures the round's pad, which is the one a
/// player spends a series on.
Future<void> _reachTheRoundKeypad(WidgetTester tester) async {
  await launchOnTheHome(tester);

  await tester.ensureVisible(find.text('Empezar la serie'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Empezar la serie'));
  for (int i = 0; i < 20 && find.byType(RoundScreen).evaluate().isEmpty; i++) {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  }
  expect(find.byType(RoundScreen), findsOneWidget, reason: 'the series never opened');
}

/// The painted decoration of one key, by the digit on its face.
BoxDecoration _decorationOfKey(WidgetTester tester, String id) {
  final Finder key = find.byWidgetPredicate(
    (Widget w) => w is KeypadKeyView && w.data.id == id,
  );
  final Container container = tester.widget<Container>(
    find.descendant(
      of: find.descendant(of: key, matching: find.byType(PressableSurface)),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

/// Where the *painted* surface of a key is.
///
/// **Not the `PressableSurface` widget's own box.** That box never moves: the
/// shadow's space is reserved on both axes at all times and the surface travels
/// *within* it, by a padding that swaps sides. Measuring the outer widget reads
/// `Offset.zero` on a key that is visibly sunk — which is what the first run of
/// this test did, on the device, and it looked like the travel not happening.
Offset _paintedTopLeftOfKey(WidgetTester tester, String id) => tester.getTopLeft(
      find.descendant(
        of: find.descendant(
          of: find.byWidgetPredicate(
            (Widget w) => w is KeypadKeyView && w.data.id == id,
          ),
          matching: find.byType(PressableSurface),
        ),
        matching: find.byType(Container),
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a key sinks into its own shadow while it is held, on the device',
      (WidgetTester tester) async {
    await _reachTheRoundKeypad(tester);

    final Finder pad = find.byWidgetPredicate(
      (Widget w) => w is KeypadKeyView && w.data.id == '7',
    );
    expect(pad, findsOneWidget, reason: 'never reached a keypad');

    final BoxDecoration resting = _decorationOfKey(tester, '7');
    expect(resting.boxShadow, hasLength(1));
    expect(resting.boxShadow!.single.offset, BrandShape.shadowTile);
    expect(resting.boxShadow!.single.blurRadius, 0);
    expect(resting.boxShadow!.single.spreadRadius, 0);
    final Offset restingAt = _paintedTopLeftOfKey(tester, '7');

    final TestGesture gesture = await tester.startGesture(tester.getCenter(pad));
    await tester.pump();

    expect(
      _decorationOfKey(tester, '7').boxShadow,
      isEmpty,
      reason: 'the shadow should be gone, not merely smaller',
    );
    expect(
      _paintedTopLeftOfKey(tester, '7') - restingAt,
      BrandShape.shadowTile,
      reason: 'the travel is the shadow\'s own offset, so a surface with a '
          'deeper shadow sinks further — measured against the token rather '
          'than a fixed number, which is the relationship that would break',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_decorationOfKey(tester, '7').boxShadow, hasLength(1));
    expect(_paintedTopLeftOfKey(tester, '7'), restingAt);
  });

  testWidgets('and a key that is unavailable does not travel under a thumb, '
      'which the case above passes without', (WidgetTester tester) async {
    await _reachTheRoundKeypad(tester);

    final Finder unavailable = find.byWidgetPredicate(
      (Widget w) => w is KeypadKeyView && !w.available,
    );
    if (unavailable.evaluate().isEmpty) {
      debugPrint('  press travel · no unavailable key on this pad; control not exercised');
      return;
    }

    expect(
      find.descendant(of: unavailable.first, matching: find.byType(IgnorePointer)),
      findsWidgets,
      reason: 'an unavailable key is protected by IgnorePointer, not by '
          'absence: it keeps its PressableSurface, and has to, so that its '
          'size, radius and resting shadow stop the pad reflowing when a key '
          'becomes unavailable. The widget\'s own comment claimed the surface '
          'was absent; it never was, and this is what found the two out of '
          'step.',
    );

    final KeypadKeyView key = tester.widget<KeypadKeyView>(unavailable.first);
    final Offset before = _paintedTopLeftOfKey(tester, key.data.id);

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(unavailable.first));
    await tester.pump();

    expect(_paintedTopLeftOfKey(tester, key.data.id), before,
        reason: 'it must not sink');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
