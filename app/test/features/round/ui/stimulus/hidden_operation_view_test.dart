import 'package:akimath_app/design/widgets/candy_surface.dart';
import 'package:akimath_app/features/round/ui/stimulus/hidden_operation_view.dart';
import 'package:flutter/material.dart';
import 'package:akimath_app/design/icons/brand_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frozen golden: `2 › 7`, `5 › 16`, query 9. The rule is `×3 + 1`.
const List<({int input, int output})> _tripleAndOne =
    <({int input, int output})>[
  (input: 2, output: 7),
  (input: 5, output: 16),
];

Future<void> _pump(
  WidgetTester tester, {
  List<({int input, int output})> examples = _tripleAndOne,
  int queryInput = 9,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: HiddenOperationView(
              examples: examples,
              queryInput: queryInput,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('nothing between two numbers reads as arithmetic', () {
    testWidgets(
        'the mark between two numbers is mapsTo and never forward, asked of '
        'the glyph rather than of a character — a chevron set between numerals '
        'reads as the false claim 2 > 4',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('›'), findsNothing);
      expect(find.text('>'), findsNothing);

      final Iterable<BrandGlyph> bridges = tester
          .widgetList<BrandIcon>(find.byType(BrandIcon))
          .map((BrandIcon icon) => icon.glyph);
      expect(bridges, isNotEmpty);
      expect(bridges, everyElement(isNot(BrandGlyph.forward)));
      expect(bridges, contains(BrandGlyph.mapsTo));
    });
  });


  group('the machine shows its workings and one question', () {
    testWidgets('both examples are drawn whole', (WidgetTester tester) async {
      await _pump(tester);

      for (final String value in <String>['2', '7', '5', '16']) {
        expect(find.text(value), findsOneWidget, reason: value);
      }
    });

    testWidgets('the query has an input and a hole',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text('9'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
      expect(find.byType(CandySurface), findsNWidgets(6),
          reason: 'two examples plus the query: three rows, two tiles each');
    });

    testWidgets('a third example makes a third row',
        (WidgetTester tester) async {
      await _pump(
        tester,
        examples: const <({int input, int output})>[
          (input: 1, output: 4),
          (input: 2, output: 7),
          (input: 3, output: 10),
        ],
      );

      expect(find.byType(CandySurface), findsNWidgets(8));
      expect(find.text('10'), findsOneWidget);
    });
  });

  group('the query is below the examples, not among them', () {
    testWidgets(
        'the hole sits under every worked output, which is what makes it a '
        'question rather than a fourth example — an interleaved layout would '
        'still draw six tiles and still find every value',
        (WidgetTester tester) async {
      await _pump(tester);

      final double hole = tester.getCenter(find.text('?')).dy;

      expect(tester.getCenter(find.text('7')).dy, lessThan(hole));
      expect(tester.getCenter(find.text('16')).dy, lessThan(hole));
      expect(tester.getCenter(find.text('9')).dy,
          moreOrLessEquals(hole, epsilon: 0.5),
          reason: 'the query input shares its row with the hole');
    });

    testWidgets(
        'each example keeps its input beside its own output, because '
        'transposing the rows would pair 2 with 16 — a different and '
        'unsolvable question',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(tester.getCenter(find.text('2')).dy,
          moreOrLessEquals(tester.getCenter(find.text('7')).dy, epsilon: 0.5));
      expect(tester.getCenter(find.text('5')).dy,
          moreOrLessEquals(tester.getCenter(find.text('16')).dy, epsilon: 0.5));
      expect(tester.getCenter(find.text('2')).dx,
          lessThan(tester.getCenter(find.text('7')).dx));
    });
  });

  group('the hole is distinguishable without hue', () {
    testWidgets('exactly one tile is dashed', (WidgetTester tester) async {
      await _pump(tester);

      final List<CandySurface> tiles =
          tester.widgetList<CandySurface>(find.byType(CandySurface)).toList();
      final Iterable<CandySurface> dashed =
          tiles.where((CandySurface t) => t.borderDash != null);

      expect(dashed, hasLength(1));
      expect(dashed.single.background, isNot(tiles.first.background));
    });
  });

  group('Aki is not here', () {
    testWidgets(
        'nothing in the machine draws her, because she does not appear while '
        'the learner is solving — the implementation plan sketches this family '
        'with her tail curl, and the invariant outranks the sketch',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.bySemanticsLabel('Aki'), findsNothing);
    });
  });

  group('it survives real content', () {
    testWidgets('three-digit outputs still fit', (WidgetTester tester) async {
      await _pump(
        tester,
        examples: const <({int input, int output})>[
          (input: 10, output: 100),
          (input: 25, output: 250),
        ],
        queryInput: 40,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('250'), findsOneWidget);
    });
  });
}
