import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/features/puzzle/ui/word_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WordSearchPuzzle _puzzle() => const WordSearchPuzzle(
      grid: <String>['SUMAX', 'CYZWB', 'EDFGH', 'RIJKL', 'ONPQT'],
      words: <String>['SUMA', 'CERO'],
      tutorialSteps: <String>['Busca las palabras.'],
      referenceSheet: <String>['Las palabras van en ocho direcciones.'],
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: WordSearchScreen(puzzle: _puzzle())),
  );
  await tester.pumpAndSettle();
}

/// Drags across the named letters in order, each of which is unique in this
/// grid, and releases.
Future<void> _trace(WidgetTester tester, List<String> letters) async {
  final TestGesture gesture =
      await tester.startGesture(tester.getCenter(find.text(letters.first)));
  for (final String letter in letters.skip(1)) {
    await gesture.moveTo(tester.getCenter(find.text(letter)));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The word as it appears in the list, not in the grid.
Finder _inList(String word) => find.byWidgetPredicate(
      (Widget w) => w is Text && w.data == word,
    );

TextDecoration? _decorationOf(WidgetTester tester, String word) =>
    tester.widget<Text>(_inList(word)).style?.decoration;

Future<int Function()> _pumpCountingPractice(WidgetTester tester) async {
  int practised = 0;
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: WordSearchScreen(
        puzzle: _puzzle(),
        onPractised: () => practised++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => practised;
}

void main() {
  group('claiming a word is practice', () {
    testWidgets('the first word claimed reports it, once',
        (WidgetTester tester) async {
      final int Function() practised = await _pumpCountingPractice(tester);
      expect(practised(), 0, reason: 'opening a puzzle is not practice');

      await _trace(tester, <String>['S', 'U', 'M', 'A']);
      expect(practised(), 1);

      await _trace(tester, <String>['C', 'E', 'R', 'O']);
      expect(practised(), 1, reason: 'the day is recorded once, not per word');
    });

    testWidgets('a trace that spells nothing is not practice',
        (WidgetTester tester) async {
      final int Function() practised = await _pumpCountingPractice(tester);

      await _trace(tester, <String>['S', 'C', 'E', 'R', 'O']);
      expect(practised(), 0);

      await _trace(tester, <String>['S', 'U', 'M', 'A']);
      expect(practised(), 1, reason: 'a word still counts afterwards');
    });
  });


  group('the screen shows a grid and a list', () {
    testWidgets('every letter is drawn, read off two that appear nowhere in '
        'the word list', (WidgetTester tester) async {
      await _pump(tester);
      expect(find.text('X'), findsOneWidget);
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('every word is listed', (WidgetTester tester) async {
      await _pump(tester);
      expect(_inList('SUMA'), findsOneWidget);
      expect(_inList('CERO'), findsOneWidget);
    });
  });

  group('nothing is typed here', () {
    testWidgets('there is no keypad, since a pad on a puzzle that takes no '
        'digits is a control with nothing to do',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.byType(Keypad), findsNothing);
      expect(find.byType(KeypadKeyView), findsNothing);
    });
  });

  group('a word is claimed by dragging across it', () {
    testWidgets('the found word is struck through', (WidgetTester tester) async {
      await _pump(tester);
      expect(_decorationOf(tester, 'SUMA'), TextDecoration.none);

      await _trace(tester, <String>['S', 'U', 'M', 'A']);

      expect(_decorationOf(tester, 'SUMA'), TextDecoration.lineThrough);
      expect(_decorationOf(tester, 'CERO'), TextDecoration.none,
          reason: 'claiming one word must not strike the other');
    });

    testWidgets('a line that spells nothing claims nothing, as S-C-E-R-O down '
        'the first column does not', (WidgetTester tester) async {
      await _pump(tester);
      await _trace(tester, <String>['S', 'C', 'E', 'R', 'O']);

      expect(_decorationOf(tester, 'SUMA'), TextDecoration.none);
      expect(_decorationOf(tester, 'CERO'), TextDecoration.none);
    });

    testWidgets('a word read backwards counts, so nobody has to guess the '
        'author\'s direction', (WidgetTester tester) async {
      await _pump(tester);
      await _trace(tester, <String>['A', 'M', 'U', 'S']);

      expect(_decorationOf(tester, 'SUMA'), TextDecoration.lineThrough);
    });

    testWidgets('a drag that leaves the grid claims nothing, because letterAt '
        'answers null outside rather than the nearest cell',
        (WidgetTester tester) async {
      await _pump(tester);

      final Offset start = tester.getCenter(find.text('S'));
      final TestGesture gesture = await tester.startGesture(start);
      await gesture.moveTo(tester.getCenter(find.text('U')));
      await gesture.moveTo(const Offset(-50, 400));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_decorationOf(tester, 'SUMA'), TextDecoration.none);
    });

    testWidgets('the last word solves it', (WidgetTester tester) async {
      int solved = 0;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: WordSearchScreen(puzzle: _puzzle(), onSolved: () => solved++),
        ),
      );
      await tester.pumpAndSettle();

      await _trace(tester, <String>['S', 'U', 'M', 'A']);
      expect(solved, 0, reason: 'one word of two is not solved');

      await _trace(tester, <String>['C', 'E', 'R', 'O']);
      expect(solved, 1);
    });
  });

  group('the way out and the rules', () {
    testWidgets('there is one way out', (WidgetTester tester) async {
      bool closed = false;
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: WordSearchScreen(
            puzzle: _puzzle(),
            onClose: () => closed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == 'Salir',
      ));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('the rules come from the pack, on demand',
        (WidgetTester tester) async {
      await _pump(tester);
      expect(find.textContaining('ocho direcciones'), findsNothing);

      await tester.tap(find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == 'Cómo se juega',
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('ocho direcciones'), findsOneWidget);
    });
  });
}
