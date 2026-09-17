import 'package:akimath_app/design/math/spec/es_mx_number.dart';
import 'package:akimath_app/features/round/ui/stimulus/number_series_view.dart';
import 'package:akimath_app/design/widgets/candy_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the series the way the app builds it.
///
/// Inside a scaling `FittedBox`, which is how `RoundScreen` draws every prompt
/// — a series pumped bare wraps onto a second line and looks like two series,
/// and a test that pumps a shape the app never builds is a gate checking
/// something nobody ships.
Future<void> _pump(
  WidgetTester tester,
  List<int> terms, {
  required int unknownIndex,
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
            child: NumberSeriesView(terms: terms, unknownIndex: unknownIndex),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a series shows its terms and one hole', () {
    testWidgets('every visible term is drawn, in order',
        (WidgetTester tester) async {
      await _pump(tester, <int>[2, 4, 6, 8], unknownIndex: 3);

      for (final int term in <int>[2, 4, 6]) {
        expect(find.text(EsMxNumber.integer(term)), findsOneWidget);
      }
    });

    testWidgets('there is exactly one blank, and it is where the payload says',
        (WidgetTester tester) async {
      await _pump(tester, <int>[2, 4, 6, 8], unknownIndex: 1);

      expect(find.text('?'), findsOneWidget);
      expect(find.byType(CandySurface), findsNWidgets(4));

      final double first = tester.getCenter(find.text('2')).dx;
      final double blank = tester.getCenter(find.text('?')).dx;
      final double third = tester.getCenter(find.text('6')).dx;
      expect(blank, greaterThan(first),
          reason: 'the hole is a position, not a suffix');
      expect(blank, lessThan(third),
          reason: 'pinning the geometry is what fails an always-last renderer');
    });

    testWidgets(
        'the hidden term is never drawn, which is the renderer\'s job because '
        'the payload carries the true value for offline grading and replay',
        (WidgetTester tester) async {
      await _pump(tester, <int>[2, 6, 18, 54, 162],
          unknownIndex: 4);

      expect(find.text('162'), findsNothing);
    });

    testWidgets(
        'a hole at either end is still one hole — the two positions a loop is '
        'likeliest to mishandle, so both are pumped rather than assumed',
        (WidgetTester tester) async {
      for (final int index in <int>[0, 3]) {
        await _pump(tester, <int>[5, 10, 15, 20],
            unknownIndex: index);

        expect(find.text('?'), findsOneWidget, reason: 'index $index');
        expect(find.byType(CandySurface), findsNWidgets(4),
            reason: 'index $index');
        expect(find.text(EsMxNumber.integer(<int>[5, 10, 15, 20][index])),
            findsNothing,
            reason: 'index $index');
      }
    });
  });

  group('the hole is distinguishable without hue', () {
    testWidgets(
        'it is dashed and the given terms are not, so the outline pattern '
        'carries the difference and the fill only reinforces it — deuteranopia '
        'collapses a good deal of the palette, and the verdict ring already '
        'follows this rule',
        (WidgetTester tester) async {
      await _pump(tester, <int>[2, 4, 6], unknownIndex: 2);

      final List<CandySurface> tiles =
          tester.widgetList<CandySurface>(find.byType(CandySurface)).toList();

      expect(tiles, hasLength(3));
      expect(
        tiles.take(2).every((CandySurface t) => t.borderDash == null),
        isTrue,
        reason: 'a given term should be solid',
      );
      expect(tiles.last.borderDash, isNotNull, reason: 'the hole should be dashed');
    });

    testWidgets('and it is filled differently too', (WidgetTester tester) async {
      await _pump(tester, <int>[2, 4, 6], unknownIndex: 2);

      final List<CandySurface> tiles =
          tester.widgetList<CandySurface>(find.byType(CandySurface)).toList();

      expect(tiles.last.background, isNot(tiles.first.background));
    });

    testWidgets(
        'the dash follows the hole rather than the last tile, told apart by '
        'putting the hole first',
        (WidgetTester tester) async {
      await _pump(tester, <int>[2, 4, 6], unknownIndex: 0);

      final List<CandySurface> tiles =
          tester.widgetList<CandySurface>(find.byType(CandySurface)).toList();

      expect(tiles.first.borderDash, isNotNull);
      expect(tiles.last.borderDash, isNull);
    });
  });

  group('it survives real content', () {
    testWidgets('a five-term series and a three-digit term both fit',
        (WidgetTester tester) async {
      await _pump(tester, <int>[1, 1, 2, 3, 5], unknownIndex: 4);
      expect(tester.takeException(), isNull);

      await _pump(tester, <int>[2, 6, 18, 162], unknownIndex: 0);
      expect(tester.takeException(), isNull);
      expect(find.text('162'), findsOneWidget);
    });

    testWidgets(
        'a four-digit term is written the es-MX way, a decision that lives '
        'here because the terms arrive as integers — a pack shipping "1000" '
        'as a string would put the grouping beyond the reach of any gate',
        (WidgetTester tester) async {
      await _pump(tester, <int>[250, 500, 1000, 2000], unknownIndex: 3);

      expect(find.text(EsMxNumber.integer(1000)), findsOneWidget);
      expect(find.text('1000'), findsNothing);
    });
  });
}
