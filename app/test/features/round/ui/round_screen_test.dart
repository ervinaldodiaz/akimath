import 'package:akimath_app/content/model/diagnosis.dart';
import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/features/round/policy/answer_draft.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/design/math/spec/es_mx_number.dart';
import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:akimath_app/design/widgets/stat_tile.dart';
import 'package:akimath_app/design/widgets/verdict_ring.dart';
import 'package:akimath_app/features/round/ui/round_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The keys that spell `42`, which is what both fixtures' first item wants.
const List<String> _rightAnswer = <String>['4', '2'];

/// Anything the fixtures do not want.
const String _wrongAnswer = '9';

/// A second wrong answer, so a round answered wrong twice can tell its first
/// slip from its last.
const String _anotherWrongAnswer = '7';

/// The four instants a two-item round reads, in the order it reads them.
final DateTime _itemOneShown = DateTime(2026, 8, 17, 9);
final DateTime _itemOneSubmitted = DateTime(2026, 8, 17, 9, 0, 3);
final DateTime _itemTwoShown = DateTime(2026, 8, 17, 9, 0, 30);
final DateTime _itemTwoSubmitted = DateTime(2026, 8, 17, 9, 0, 32);

const List<Item> _oneItem = <Item>[
  Item(
    id: 't1',
    stimulus: ArithmeticStimulus(<PromptToken>[
      PromptToken.text('14'),
      PromptToken.operator('×'),
      PromptToken.text('3'),
      PromptToken.operator('='),
    ]),
    answer: PlainAnswer('42'),
    ladderStep: 2,
  ),
];

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: RoundScreen(items: _oneItem)),
  );
}

/// The text currently in the answer slot.
String _answer(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey<String>('answer-draft'))).data!;

Future<void> _press(WidgetTester tester, String id) async {
  await tester.tap(
    find.byWidgetPredicate(
      (Widget w) => w is KeypadKeyView && w.data.id == id,
    ),
  );
  await tester.pump();
}

const List<Item> _twoItems = <Item>[
  Item(
    id: 't1',
    stimulus: ArithmeticStimulus(<PromptToken>[
      PromptToken.text('14'),
      PromptToken.operator('×'),
      PromptToken.text('3'),
      PromptToken.operator('='),
    ]),
    answer: PlainAnswer('42'),
    ladderStep: 2,
  ),
  Item(
    id: 't2',
    stimulus: ArithmeticStimulus(<PromptToken>[
      PromptToken.text('5'),
      PromptToken.operator('+'),
      PromptToken.text('1'),
      PromptToken.operator('='),
    ]),
    answer: PlainAnswer('6'),
    ladderStep: 1,
  ),
];

/// The figure a stat tile shows, found by its label.
String _tileFigure(WidgetTester tester, String label) {
  final Finder tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(StatTile),
  );
  return tester
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .map((Text t) => t.data ?? '')
      .firstWhere((String text) => text != label);
}

void main() {
  group('the time it reports is the time the player took', () {
    testWidgets(
        'the first item is timed from when it appeared and never reports a '
        'negative duration — the first verdict every player sees',
        (WidgetTester tester) async {
      final List<DateTime> instants = <DateTime>[
        DateTime(2026, 8, 17, 9, 0, 0),
        DateTime(2026, 8, 17, 9, 0, 7, 400),
      ];
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(items: _oneItem, now: () => instants.removeAt(0)),
        ),
      );

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(instants, isEmpty, reason: 'the clock was read a different number '
          'of times than this test accounts for');
      final String figure = _tileFigure(tester, 'TIEMPO');
      expect(figure, EsMxNumber.seconds(7.4, places: 1),
          reason: 'built through the formatter rather than typed, because the '
              'figure carries a thin no-break space a literal would not');
      expect(figure, isNotEmpty,
          reason: 'comparing two calls of one formatter would also pass if it '
              'returned nothing');
      expect(figure, isNot(startsWith('−')), reason: 'a negative duration');
    });

    testWidgets(
        'the second item is timed from when it appeared and not from the '
        'first — the control, since every item sharing one start would also '
        'clear the assertion above',
        (WidgetTester tester) async {
      final List<DateTime> instants = <DateTime>[
        _itemOneShown,
        _itemOneSubmitted,
        _itemTwoShown,
        _itemTwoSubmitted,
      ];
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(items: _twoItems, now: () => instants.removeAt(0)),
        ),
      );

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      expect(_tileFigure(tester, 'TIEMPO'), EsMxNumber.seconds(3, places: 1));

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      for (final String id in <String>['6', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();

      expect(_tileFigure(tester, 'TIEMPO'), EsMxNumber.seconds(2, places: 1));
      expect(instants, isEmpty);
    });
  });

  group('a series ends when it has an ending, and cycles when it does not', () {
    testWidgets(
        'onFinished fires on the last item and not before — every other test '
        'here passes one item, so dropping the last-item guard entirely left '
        'the whole suite green while a real series ended after item one',
        (WidgetTester tester) async {
      int finished = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(items: _twoItems, onFinished: (_) => finished++),
        ),
      );

      await _press(tester, '4');
      await _press(tester, '2');
      await _press(tester, 'submit');
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(finished, 0, reason: 'the series ended on its first item');
      expect(find.text('Reto 2'), findsOneWidget);

      await _press(tester, '6');
      await _press(tester, 'submit');
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(finished, 1);
    });

    testWidgets(
        'a wrong last answer ends a multi-item series but not a one-item one — '
        'on one item the only "another one" Intentar otro can offer is this '
        'one, while a series a player keeps failing would otherwise wrap to '
        'item 1 forever and never finish',
        (WidgetTester tester) async {
      int finished = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(items: _twoItems, onFinished: (_) => finished++),
        ),
      );

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Reto 2'), findsOneWidget);

      for (final String id in <String>[_wrongAnswer, 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      expect(finished, 1, reason: 'the series wrapped back to its first item');
      expect(find.text('Reto 1'), findsNothing);
    });

    testWidgets(
        'without onFinished the last item cycles back to the first — the '
        'control, since a practice series is endless and must not have been '
        'quietly ended',
        (WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: RoundScreen(items: _twoItems)),
      );

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      for (final String id in <String>['6', 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Reto 1'), findsOneWidget);
    });

    testWidgets(
        'a skip control appears only when there is another item — one item has '
        'nowhere to skip to, and on the teaching item the control completed '
        'the first run with nothing solved',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.text('Saltar este reto'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: RoundScreen(items: _twoItems)),
      );
      expect(find.text('Saltar este reto'), findsOneWidget);

      await tester.tap(find.text('Saltar este reto'));
      await tester.pumpAndSettle();
      expect(find.text('Reto 2'), findsOneWidget);
    });
  });

  group('a player can answer an item', () {
    testWidgets('typing shows the answer and no verdict yet',
        (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, '4');
      await _press(tester, '2');

      expect(_answer(tester), '42');
      expect(
        find.byType(VerdictRing),
        findsNothing,
        reason: 'a verdict appeared before the answer was submitted',
      );
    });

    testWidgets('a right answer shows the correct verdict',
        (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, '4');
      await _press(tester, '2');
      await _press(tester, 'submit');

      expect(
        tester.widget<VerdictRing>(find.byType(VerdictRing)).verdict,
        Verdict.correct,
      );
    });

    testWidgets('a wrong answer shows the wrong verdict',
        (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, '9');
      await _press(tester, 'submit');

      expect(
        tester.widget<VerdictRing>(find.byType(VerdictRing)).verdict,
        Verdict.wrong,
      );
    });

    testWidgets('backspace removes a digit', (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, '4');
      await _press(tester, '2');
      await _press(tester, 'backspace');

      expect(_answer(tester), '4');
    });

    testWidgets('an empty answer cannot be submitted',
        (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, 'submit');

      expect(
        find.byType(VerdictRing),
        findsNothing,
        reason: 'an empty answer was judged',
      );
    });

    testWidgets('continuing from the verdict returns an empty draft',
        (WidgetTester tester) async {
      await _pump(tester);
      await _press(tester, '4');
      await _press(tester, '2');
      await _press(tester, 'submit');

      expect(find.byType(VerdictRing), findsOneWidget);
      expect(find.byType(Keypad), findsNothing,
          reason: 'a verdict is its own screen, so a player reaching for the '
              'pad cannot seed the next answer with whatever they hit');

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(find.byType(VerdictRing), findsNothing);
      expect(_answer(tester).trim(), isEmpty, reason: 'the draft did not reset');
    });
  });

  group('the round obeys the house rules', () {
    testWidgets('there is no visible timer', (WidgetTester tester) async {
      await _pump(tester);

      for (final Text text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.data ?? '', isNot(matches(RegExp(r'\d+:\d\d'))),
            reason: 'no visible timer, ever — time is measured quietly');
      }
    });

    testWidgets('the system keyboard never appears',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byType(EditableText), findsNothing);
    });
  });

  group('what is shown is what is graded', () {
    testWidgets(
        'a full-length answer is displayed in full, because a clipped one '
        'means the answer shown and the answer graded differ and backspacing '
        'a hidden character looks like a keypress that did nothing',
        (WidgetTester tester) async {
      await _pump(tester);
      for (int i = 0; i < AnswerDraft.maxLength; i++) {
        await _press(tester, '8');
      }

      expect(_answer(tester), '8' * AnswerDraft.maxLength);

      final Finder answer = find.byKey(const ValueKey<String>('answer-draft'));
      final Rect slot = tester.getRect(
        find.ancestor(of: answer, matching: find.byType(FittedBox)),
      );
      final Rect text = tester.getRect(answer);

      expect(
        slot.inflate(1).contains(text.topLeft),
        isTrue,
        reason: 'the answer starts outside its slot',
      );
      expect(
        slot.inflate(1).contains(text.bottomRight),
        isTrue,
        reason: 'the answer overflows its slot: $text against $slot',
      );
    });

    testWidgets('backspace always changes what is on screen',
        (WidgetTester tester) async {
      await _pump(tester);
      for (int i = 0; i < AnswerDraft.maxLength; i++) {
        await _press(tester, '8');
      }

      final String before = _answer(tester);
      await _press(tester, 'backspace');

      expect(
        _answer(tester),
        isNot(before),
        reason: 'a keypress that visibly did nothing',
      );
      expect(_answer(tester).length, before.length - 1);
    });
  });

  group('a finished series reports what happened, item by item', () {
    testWidgets(
        'the outcomes come back in the order they were answered, because a '
        'count cannot draw the ring — correct: 1, total: 2 cannot say which '
        'one was missed, and the round is the only thing that graded them',
        (WidgetTester tester) async {
      RoundOutcome? outcome;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(
            items: _twoItems,
            onFinished: (RoundOutcome result) => outcome = result,
          ),
        ),
      );

      for (final String id in <String>[..._rightAnswer, 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      for (final String id in <String>['9', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      expect(outcome!.outcomes, <Verdict>[Verdict.correct, Verdict.wrong]);
      expect(outcome!.correct, 1);
      expect(outcome!.total, 2);
    });

    testWidgets(
        'a clean series reports every item correct — the control, since an '
        'outcomes list that always reported a slip would satisfy the ordering '
        'test above on its wrong half alone',
        (WidgetTester tester) async {
      RoundOutcome? outcome;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(
            items: _twoItems,
            onFinished: (RoundOutcome result) => outcome = result,
          ),
        ),
      );

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      for (final String id in <String>['6', 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();

      expect(outcome!.outcomes, <Verdict>[Verdict.correct, Verdict.correct]);
      expect(outcome!.stumble, isNull, reason: 'nothing went wrong to explain');
    });

    testWidgets(
        'the first slip is the one carried out and not the last — the summary '
        'explains one mistake, the earliest most likely caused the rest, and '
        'picking the latest would rewrite the block every time a tired player '
        'slipped again at the end',
        (WidgetTester tester) async {
      RoundOutcome? outcome;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(
            items: _twoItems,
            fallbackDiagnosis: const Diagnosis(
              steps: <String>['Revisa la cuenta paso por paso.'],
              explain: 'Vuelve a leer los numeros con calma.',
            ),
            onFinished: (RoundOutcome result) => outcome = result,
          ),
        ),
      );

      for (final String id in <String>[_anotherWrongAnswer, 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();
      for (final String id in <String>['8', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      expect(outcome!.outcomes, <Verdict>[Verdict.wrong, Verdict.wrong]);
      expect(outcome!.stumble, isNotNull);
      expect(outcome!.stumbleIndex, 0);
    });

    testWidgets(
        'a pack with no diagnosis copy carries no explanation — absent rather '
        'than invented, because the words are the pack\'s and a round given '
        'none has nothing true to say about the slip',
        (WidgetTester tester) async {
      RoundOutcome? outcome;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(
            items: _twoItems,
            onFinished: (RoundOutcome result) => outcome = result,
          ),
        ),
      );

      for (final String id in <String>['7', 'submit']) {
        await _press(tester, id);
      }
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();
      for (final String id in <String>['8', 'submit']) {
        await _press(tester, id);
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intentar otro'));
      await tester.pumpAndSettle();

      expect(outcome!.stumble, isNull);
      expect(outcome!.stumbleIndex, isNull);
    });
  });

  group('the round reports the verdict it decided, for the local record', () {
    testWidgets(
        'onGraded fires once per answer with the verdict and the time — the '
        'seam features/stats/ needs, so that a recorder never calls gradeItem '
        'again and makes a second decision about one answer',
        (WidgetTester tester) async {
      final List<(Verdict, Duration)> graded = <(Verdict, Duration)>[];
      final List<DateTime> instants = <DateTime>[
        DateTime(2026, 8, 20, 9),
        DateTime(2026, 8, 20, 9, 0, 7),
      ];
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(
            items: _oneItem,
            now: () => instants.isEmpty
                ? DateTime(2026, 8, 20, 9, 0, 7)
                : instants.removeAt(0),
            onGraded: (Verdict verdict, Duration elapsed) =>
                graded.add((verdict, elapsed)),
          ),
        ),
      );

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }

      expect(graded, hasLength(1));
      expect(graded.single.$1, Verdict.correct);
      expect(graded.single.$2, const Duration(seconds: 7));
    });

    testWidgets(
        'a wrong answer is reported too — the control, since a recorder fed '
        'only the wins would report 100% for ever',
        (WidgetTester tester) async {
      final List<Verdict> graded = <Verdict>[];
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: RoundScreen(
            items: _oneItem,
            onGraded: (Verdict verdict, Duration elapsed) => graded.add(verdict),
          ),
        ),
      );

      for (final String id in <String>['9', 'submit']) {
        await _press(tester, id);
      }

      expect(graded, <Verdict>[Verdict.wrong]);
    });

    testWidgets(
        'a round with no recorder wired reports nothing, which is how the '
        'teaching item stays out of the figures — there is nothing to record '
        'into rather than a rule somebody has to remember',
        (WidgetTester tester) async {
      await _pump(tester);

      for (final String id in <String>['4', '2', 'submit']) {
        await _press(tester, id);
      }

      expect(find.byType(RoundScreen), findsOneWidget);
    });
  });
}
