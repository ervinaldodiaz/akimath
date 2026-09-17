import 'package:akimath_app/design/math/spec/es_mx_number.dart';
import 'package:akimath_app/design/widgets/candy_surface.dart';
import 'package:akimath_app/features/round/ui/stimulus/matrix_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frozen golden: a 3×3 multiplication table with the corner missing.
const List<int> _table = <int>[1, 2, 3, 2, 4, 6, 3, 6, 9];

/// Pumps the grid the way the app builds it.
///
/// Inside a scaling `FittedBox`, which is how `RoundScreen` draws every prompt.
/// A test that pumps a shape the app never builds is a gate checking something
/// nobody ships.
Future<void> _pump(
  WidgetTester tester, {
  List<int> cells = _table,
  int size = 3,
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
            child: MatrixView(
              cells: cells,
              size: size,
              unknownIndex: unknownIndex,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a grid draws every cell but the hole', () {
    testWidgets('nine cells, one of them blank', (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 8);

      expect(find.byType(CandySurface), findsNWidgets(9));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets(
        'the hidden cell is never drawn — cells[8] is 9 and 9 appears nowhere '
        'else in the table, so finding none means the hole really hides it',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 8);

      expect(find.text('9'), findsNothing);
      expect(find.text('6'), findsNWidgets(2));
    });

    testWidgets('a 2×2 is four cells, not nine', (WidgetTester tester) async {
      await _pump(
        tester,
        cells: <int>[1, 2, 2, 4],
        size: 2,
        unknownIndex: 3,
      );

      expect(find.byType(CandySurface), findsNWidgets(4));
      expect(find.text('4'), findsNothing);
    });
  });

  group('the cells are laid out in reading order', () {
    testWidgets(
        'index 1 is right of index 0 and index 3 below it, so a row-major '
        'grid is not transposed — read by position rather than by value, '
        'because the table is symmetric and the two 2s are alike',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 8);

      final Offset first = tester.getCenter(find.text('1'));
      final List<Offset> twos = tester
          .widgetList<Text>(find.text('2'))
          .map((Text t) => tester.getCenter(find.byWidget(t)))
          .toList();

      expect(twos, hasLength(2));
      final Offset across = twos.firstWhere((Offset o) => o.dx > first.dx);
      final Offset down = twos.firstWhere((Offset o) => o.dy > first.dy);

      expect(across.dy, moreOrLessEquals(first.dy, epsilon: 0.5),
          reason: 'the row neighbour should share the top row');
      expect(down.dx, moreOrLessEquals(first.dx, epsilon: 0.5),
          reason: 'the column neighbour should share the first column');
    });

    testWidgets(
        'the hole lands where its index says — index 2 is top-right, and a '
        'transposition would put it bottom-left with every count above passing',
        (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 2);

      final Offset hole = tester.getCenter(find.text('?'));
      final Offset topLeft = tester.getCenter(find.text('1'));
      final Offset bottomLeft = tester.getCenter(find.text('3').first);

      expect(hole.dx, greaterThan(topLeft.dx));
      expect(hole.dy, moreOrLessEquals(topLeft.dy, epsilon: 0.5));
      expect(hole.dy, lessThan(bottomLeft.dy));
    });
  });

  group('the hole is distinguishable without hue', () {
    testWidgets('only the hole is dashed', (WidgetTester tester) async {
      await _pump(tester, unknownIndex: 4);

      final List<CandySurface> tiles =
          tester.widgetList<CandySurface>(find.byType(CandySurface)).toList();
      final Iterable<CandySurface> dashed =
          tiles.where((CandySurface t) => t.borderDash != null);

      expect(tiles, hasLength(9));
      expect(dashed, hasLength(1));
      expect(dashed.single.background, isNot(tiles.first.background));
    });
  });

  group('it survives real content', () {
    testWidgets('a grid of three-digit cells still fits 390',
        (WidgetTester tester) async {
      await _pump(
        tester,
        cells: <int>[100, 200, 300, 200, 400, 600, 300, 600, 900],
        unknownIndex: 8,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(EsMxNumber.integer(600)), findsNWidgets(2));
    });
  });
}
