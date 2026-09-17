import 'dart:convert';

import 'package:akimath_app/content/pack_reader.dart';
import 'package:akimath_app/features/home/data/day_log_store.dart';
import 'package:akimath_app/features/home/ui/home_route.dart';
import 'package:akimath_app/features/home/ui/home_screen.dart';
import 'package:akimath_app/features/round/policy/series_plan.dart';
import 'package:akimath_app/features/round/ui/round_screen.dart';
import 'package:akimath_app/features/round/ui/summary/series_summary_screen.dart';
import 'package:akimath_app/design/widgets/icon_button_tile.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:akimath_app/design/widgets/verdict_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.source);
  final String source;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(source));
}

/// Item ids run `a0`..`a7` and item `aN` wants `N + 1`, so the sixth wants 6.
const String _answerToTheSixthItem = '6';

/// Anything but the `1` the first item wants.
const String _wrongAnswerToTheFirstItem = '9';

/// A pack of eight, so a five-item series is genuinely a subset.
String _pack(int count) {
  final List<String> items = List<String>.generate(
    count,
    (int i) => '''
    {
      "id": "a$i",
      "ladder_step": 1,
      "answer": "${i + 1}",
      "prompt": [
        {"kind": "text", "value": "${i + 1}"},
        {"kind": "operator", "glyph": "+"},
        {"kind": "text", "value": "0"},
        {"kind": "operator", "glyph": "="}
      ]
    }''',
  );
  return '''
{
  "pack_version": 1,
  "pack_id": "flow",
  "issued_at": "2026-08-01T00:00:00Z",
  "expires_at": "2099-01-01T00:00:00Z",
  "items": [${items.join(',')}]
}
''';
}

/// Unmounts, then mounts again over the same storage — the only thing that
/// makes the second mount a launch rather than a rebuild.
Future<void> _relaunchOverTheSameStorage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await _pump(tester);
}

Future<void> _pump(WidgetTester tester, {int packSize = 8}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: HomeRoute(
        reader: PackReader(bundle: _FakeBundle(_pack(packSize))),
        dayLog: InMemoryDayLogStore(),
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

/// Answers whatever item is on screen correctly and acknowledges the verdict.
Future<void> _answer(WidgetTester tester, int answer) async {
  await _press(tester, '$answer');
  await _press(tester, 'submit');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Siguiente'));
  await tester.pumpAndSettle();
}

/// How many marks on the summary's ring carry [verdict].
int _marks(WidgetTester tester, Verdict verdict) => tester
    .widgetList<VerdictRing>(find.byType(VerdictRing))
    .where((VerdictRing ring) => ring.verdict == verdict)
    .length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('a series is five items and then it ends', () {
    testWidgets('the fifth answer brings the summary, not a sixth item',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();

      for (int i = 1; i <= seriesLength; i++) {
        expect(find.text('Reto $i'), findsOneWidget, reason: 'at item $i');
        await _answer(tester, i);
      }

      expect(find.byType(SeriesSummaryScreen), findsOneWidget);
      expect(find.byType(RoundScreen), findsNothing);
      expect(find.byType(Keypad), findsNothing);
    });

    testWidgets(
        'it does not wrap back to the first item, which a test that only '
        'counted to five would miss for a round that then offered a sixth',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();

      for (int i = 1; i <= seriesLength; i++) {
        await _answer(tester, i);
      }

      expect(find.text('Reto 1'), findsNothing);
      expect(find.text('Reto 6'), findsNothing);
    });

    testWidgets('the summary reports the series, and the way back works',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();

      for (int i = 1; i <= seriesLength; i++) {
        await _answer(tester, i);
      }

      expect(_marks(tester, Verdict.correct), 5,
          reason: 'the ring and not "5 de 5" — the words are the fallback for '
              'a caller that hands over no outcomes, and HomeRoute hands the '
              "round's over");
      expect(_marks(tester, Verdict.wrong), 0);

      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SeriesSummaryScreen), findsNothing);
    });

    testWidgets(
        'a wrong answer is counted as such — the control, since five correct '
        'marks above is also what a screen drawing one mark per item '
        'regardless of its verdict would draw',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();

      await _press(tester, _wrongAnswerToTheFirstItem);
      await _press(tester, 'submit');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      for (int i = 2; i <= seriesLength; i++) {
        await _answer(tester, i);
      }

      expect(_marks(tester, Verdict.correct), 4);
      expect(_marks(tester, Verdict.wrong), 1,
          reason: 'the ring says which one, which "4 de 5" never could');
    });
  });

  group('the streak survives the series', () {
    testWidgets('playing records today, and the home shows it afterwards',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();
      for (int i = 1; i <= seriesLength; i++) {
        await _answer(tester, i);
      }
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('1 DÍA'), findsOneWidget,
          reason: 'the whole label and never a bare "1", which would pass on '
              "the preview card's arithmetic instead (PROC-11)");
    });
  });

  group('a second series is not the first series again', () {
    testWidgets(
        'the next series starts where the last one stopped — a pack of eight, '
        'five served, so the second series opens on the sixth',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();
      for (int i = 1; i <= seriesLength; i++) {
        await _answer(tester, i);
      }
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();

      await _press(tester, _answerToTheSixthItem);
      await _press(tester, 'submit');
      await tester.pumpAndSettle();

      expect(
        find.text('Siguiente'),
        findsOneWidget,
        reason: 'the second series reopened on an item already answered',
      );
    });

    testWidgets(
        'and it survives a relaunch, since advancing only in memory would give '
        'the same five every time the app opened',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();
      for (int i = 1; i <= seriesLength; i++) {
        await _answer(tester, i);
      }
      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      await _relaunchOverTheSameStorage(tester);

      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();
      await _press(tester, _answerToTheSixthItem);
      await _press(tester, 'submit');
      await tester.pumpAndSettle();

      expect(find.text('Siguiente'), findsOneWidget);
    });

    testWidgets(
        'leaving a series halfway does not consume its items, because the '
        'cursor advances on finishing — a player who closed after one item has '
        'not been served five in any sense worth remembering',
        (WidgetTester tester) async {
      await _pump(tester);
      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();
      await _answer(tester, 1);

      await tester.tap(find.byType(IconButtonTile).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Empezar la serie'));
      await tester.pumpAndSettle();
      await _press(tester, '1');
      await _press(tester, 'submit');
      await tester.pumpAndSettle();

      expect(find.text('Siguiente'), findsOneWidget);
    });
  });
}
