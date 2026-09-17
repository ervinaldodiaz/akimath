import 'package:akimath_app/design/widgets/candy_surface.dart';
import 'package:akimath_app/features/round/ui/stimulus/analogy_view.dart';
import 'package:flutter/material.dart';
import 'package:akimath_app/design/icons/brand_icon.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frozen golden: `2 › 4 como 5 › 10`, with the last term hidden.
const List<int> _doubling = <int>[2, 4, 5, 10];

Future<void> _pump(
  WidgetTester tester, {
  List<int> terms = _doubling,
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
            child: AnalogyView(terms: terms, unknownIndex: unknownIndex),
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
      await _pump(tester, unknownIndex: 3);

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


  group('an analogy draws four terms and a bridge', () {
    testWidgets('three values, one hole, one bridge',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 3);

      expect(find.text('2'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
      expect(
        find.text(AnalogyView.bridgeLabel.toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('the hidden term is never drawn', (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 3);

      expect(find.text('10'), findsNothing);
    });

    testWidgets(
        'the hole can sit in the first pair too, because unknown_index walks '
        'all four terms and a renderer assuming it is last would draw the '
        'answer',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 1);

      expect(find.text('4'), findsNothing);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('the bridge separates the two pairs', () {
    testWidgets(
        'two terms fall each side of it, so a reader sees two statements and '
        'not four loose numbers — without this the bridge could render '
        'anywhere and every count above would still pass',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 3);

      final double bridge =
          tester.getCenter(find.text(AnalogyView.bridgeLabel.toUpperCase())).dx;

      expect(tester.getCenter(find.text('2')).dx, lessThan(bridge));
      expect(tester.getCenter(find.text('4')).dx, lessThan(bridge));
      expect(tester.getCenter(find.text('5')).dx, greaterThan(bridge));
      expect(tester.getCenter(find.text('?')).dx, greaterThan(bridge));
    });
  });

  group('the hole is distinguishable without hue', () {
    testWidgets(
        'exactly one of the four tiles is dashed — the bridge is a StatPill '
        'rather than a CandySurface, so it is not among them',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 2);

      final List<CandySurface> tiles =
          tester.widgetList<CandySurface>(find.byType(CandySurface)).toList();
      final Iterable<CandySurface> dashed =
          tiles.where((CandySurface t) => t.borderDash != null);

      expect(tiles, hasLength(4));
      expect(dashed, hasLength(1));
      expect(dashed.single.background, isNot(tiles.first.background));
    });
  });

  group('it survives real content', () {
    testWidgets('three-digit terms still fit 390', (WidgetTester tester) async {
      await _pump(tester, terms: <int>[100, 300, 250, 750], unknownIndex: 3);

      expect(tester.takeException(), isNull);
      expect(find.text('250'), findsOneWidget);
    });
  });
}
