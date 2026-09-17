/// `0.3 Primer reto`, and the three exits that had to stop meaning the same
/// thing.
///
/// **The skip control.** *"Saltar este reto"* routed to `RoundScreen._next`,
/// which on the last item calls `onFinished` — so one tap completed the first
/// run permanently, with no item ever solved, one row below a close control
/// that deliberately does not. Two exits, opposite meanings, identical look.
///
/// **The retry control, which was worse.** A wrong verdict's continue button is
/// labelled *"Intentar otro"* — a request for another go — and it routed to
/// that same `_next`. So the player who answered *wrong*, the one who most
/// needs the screen that teaches the answer format, was the one who
/// permanently lost it by tapping the button the app offered them. There is no
/// reset path: no settings screen, and nothing else reads the flag.
///
/// Both are held by cases below, and both are held by their **consequence**
/// rather than by the absence of a widget: a control renamed tomorrow still
/// must not finish the teaching item.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/math/math_view.dart';
import 'package:akimath_app/design/widgets/icon_button_tile.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:akimath_app/design/widgets/stat_tile.dart';
import 'package:akimath_app/design/widgets/speech_bubble.dart';
import 'package:akimath_app/design/widgets/verdict_ring.dart';
import 'package:akimath_app/features/home/ui/home_route.dart';
import 'package:akimath_app/features/onboarding/ui/first_item_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Every asset key the widget under test asked the engine for.
///
/// `PackReader` reads through `rootBundle`, which goes over the `flutter/assets`
/// channel — so recording the channel is how "no pack is read" becomes a fact
/// about behaviour rather than a fact about the constructor's parameter list.
late List<String> assetsRequested;

/// Starts recording into [assetsRequested], and answers every load *not found*.
///
/// Answering not-found is what makes a screen that reads a pack fail visibly
/// rather than quietly succeed against a fixture no test here wrote.
///
/// **The instrument is proved before its silence is trusted** (PROC-11): "no
/// pack was requested" is also true of a harness that observes nothing, so
/// *"the recorder would have seen a pack read"* pumps `HomeRoute`, which does
/// read the pack through the same `rootBundle`.
void _recordAssetLoads() {
  assetsRequested = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) async {
    if (message != null) {
      assetsRequested.add(utf8.decode(message.buffer.asUint8List()));
    }
    return null;
  });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onFinished,
  VoidCallback? onBack,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: FirstItemScreen(
        onFinished: onFinished ?? () {},
        onBack: onBack ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String id) async {
  await tester.tap(
    find.byWidgetPredicate((Widget w) => w is KeypadKeyView && w.data.id == id),
  );
  await tester.pump();
}

/// The glyphs the compositor drew for the prompt, and only those.
///
/// **There are two `MathView`s on this screen.** The keypad's fraction key is
/// one too — `a` over a bar over `b`, at 15 px — so matching every `MathView` on
/// the screen collects the key's letters along with the expression. The prompt is
/// the one at display size.
Iterable<String> _promptGlyphs(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byWidgetPredicate(
        (Widget w) => w is MathView && w.size == MathView.defaultNumeral,
      ),
      matching: find.byType(Text),
    ))
    .map((Text t) => t.data ?? '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    _recordAssetLoads();
  });

  group('the teaching item records nothing and reports nothing', () {
    testWidgets('the prompt is the fixed teaching item, whose answer is typed '
        'rather than shown', (WidgetTester tester) async {
      await _pump(tester);

      expect(_promptGlyphs(tester), <String>['5', '+', '8', '=']);
      expect(_promptGlyphs(tester), isNot(contains('13')));
    });

    testWidgets('and 13 is what it grades as right, which the prompt alone '
        'does not pin', (WidgetTester tester) async {
      await _pump(tester);
      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(
        tester.widget<VerdictRing>(find.byType(VerdictRing)).verdict,
        Verdict.correct,
      );
    });

    testWidgets('no pack is read', (WidgetTester tester) async {
      await _pump(tester);
      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(
        assetsRequested.where((String key) => key.contains('packs')),
        isEmpty,
        reason: 'the teaching screen reached for a pack: $assetsRequested',
      );
    });

    testWidgets('the recorder would have seen a pack read',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeRoute()));
      await tester.pumpAndSettle();

      expect(
        assetsRequested.where((String key) => key.contains('packs')),
        isNotEmpty,
      );
    });

    testWidgets('answering it records no day, so no streak starts here',
        (WidgetTester tester) async {
      await _pump(tester);
      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(
        await SharedPreferencesAsync().getKeys(),
        isEmpty,
        reason: 'the tutorial wrote to storage',
      );
    });

    testWidgets('its verdict shows no streak either',
        (WidgetTester tester) async {
      await _pump(tester);
      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(find.text('RACHA'), findsOneWidget);
      final Finder streak = find.ancestor(
        of: find.text('RACHA'),
        matching: find.byType(StatTile),
      );
      final Iterable<String> figures = tester
          .widgetList<Text>(
            find.descendant(of: streak, matching: find.byType(Text)),
          )
          .map((Text t) => t.data ?? '')
          .where((String text) => text != 'RACHA');

      expect(
        figures,
        <String>['0'],
        reason: 'the tutorial claimed a streak it recorded nowhere',
      );
    });
  });

  group('Aki does not appear while the learner is solving', () {
    testWidgets('she is not in the tree', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.byType(Aki), findsNothing);
      expect(find.byType(SpeechBubble), findsNothing);
    });

    testWidgets('she returns on the verdict, so the rule is not satisfied by '
        'deleting her', (WidgetTester tester) async {
      await _pump(tester);
      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(find.byType(Aki), findsOneWidget);
    });
  });

  group('finishing and leaving are different things', () {
    testWidgets('acknowledging the verdict finishes the run',
        (WidgetTester tester) async {
      int finished = 0;
      int back = 0;
      await _pump(tester, onFinished: () => finished++, onBack: () => back++);

      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(finished, 1);
      expect(back, 0, reason: 'finishing was reported as leaving');
    });

    testWidgets('the close control leaves without finishing',
        (WidgetTester tester) async {
      int finished = 0;
      int back = 0;
      await _pump(tester, onFinished: () => finished++, onBack: () => back++);

      await tester.tap(find.byType(IconButtonTile).first);
      await tester.pumpAndSettle();

      expect(back, 1);
      expect(finished, 0, reason: 'leaving completed the first run');
    });

    testWidgets('a single item reports and stops, never composing a second '
        'one', (WidgetTester tester) async {
      int finished = 0;
      await _pump(tester, onFinished: () => finished++);

      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(finished, 1);
      expect(find.byType(VerdictRing), findsOneWidget);
      expect(find.byType(Keypad), findsNothing);
    });

    testWidgets('asking for another go is not finishing either',
        (WidgetTester tester) async {
      int finished = 0;
      await _pump(tester, onFinished: () => finished++);

      for (final String id in <String>['9', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      expect(find.text('Intentar otro'), findsOneWidget);

      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      expect(finished, 0, reason: 'a wrong answer completed the first run');
      expect(find.byType(Keypad), findsOneWidget);
      expect(_promptGlyphs(tester), <String>['5', '+', '8', '=']);
    });

    testWidgets('and then solving it does finish, so retrying did not wedge '
        'the run', (WidgetTester tester) async {
      int finished = 0;
      await _pump(tester, onFinished: () => finished++);

      for (final String id in <String>['9', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      for (final String id in <String>['1', '3', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(finished, 1);
    });

    testWidgets('there is nothing to skip, so no skip control is offered',
        (WidgetTester tester) async {
      int finished = 0;
      await _pump(tester, onFinished: () => finished++);

      expect(find.text('Saltar este reto'), findsNothing);
      expect(finished, 0);
    });
  });

  group('the house rules hold here too', () {
    testWidgets('no visible timer and no system keyboard',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.byType(EditableText), findsNothing);
      for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(matches(RegExp(r'\d+:\d\d'))));
      }
    });

    testWidgets('the keypad is the app\'s own', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byType(Keypad), findsOneWidget);
    });
  });
}
