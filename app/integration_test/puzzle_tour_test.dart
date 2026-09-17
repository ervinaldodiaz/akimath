import 'package:akimath_app/content/model/puzzle.dart';
import 'package:akimath_app/design/puzzle/cage_edge_painter.dart';
import 'package:akimath_app/design/puzzle/spec/cage_outline.dart';
import 'package:akimath_app/design/widgets/keypad.dart';
import 'package:akimath_app/features/home/ui/home_screen.dart';
import 'package:akimath_app/features/puzzle/ui/puzzle_board_view.dart';
import 'package:akimath_app/features/puzzle/ui/puzzle_screen.dart';
import 'package:akimath_app/features/puzzle/ui/word_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/launch.dart';

/// Opens every board format on a real device, and solves the one with a keypad.
///
/// The keypad it types on has existed since F0 and was wired to nothing until
/// the puzzles landed, so this was the first evidence it works at all.
///
/// **And now every format, because "five are reachable" was only ever a widget
/// test.** `home_route_test.dart` walks the shipped pack in the fake harness;
/// this walks it on a device, which is where a board that renders but cannot be
/// laid out at 390 px, or a card whose label wraps out of reach, actually
/// shows up. `f6-killer` and `f6-word-search` both left their Tier 2 open
/// waiting for exactly this.
///
/// **This suite is about the boards, so it asks for a device that is past the
/// first run** and says so, rather than carrying a first-run walk it does not
/// want behind a condition it never checked. Each case establishes that state
/// for itself: solving a board in the first one writes answered items and
/// practised steps, and a shared `setUpAll` would hand them to the second.
///
/// **Nothing about the shipped content is written down here.** `puzzlesOfDay`
/// rotates through seven boards per format, so a hardcoded solution is a test
/// that passes one day in seven — which, in a suite nothing ran, would have
/// read as flakiness rather than as a wrong assumption. The solution, the
/// format list and the line totals are all read off the live widgets.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the day\'s puzzle can be opened and solved, its solution read '
      'off the live board', (WidgetTester tester) async {
    await launchOnTheHome(tester);

    expect(find.text('ROMPECABEZAS'), findsOneWidget,
        reason: 'the section heading; the cards are under it, one per puzzle '
            'the pack carries, and tapping the heading was tapping a Text');
    await tester.ensureVisible(find.text('KenKen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KenKen'));
    for (int i = 0; i < 20 && find.byType(PuzzleScreen).evaluate().isEmpty; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
    expect(find.byType(PuzzleScreen), findsOneWidget);

    final PuzzleBoard board =
        tester.widget<PuzzleScreen>(find.byType(PuzzleScreen)).puzzle.board;
    final List<List<int>> solution = board.solution;
    final int size = board.size;
    final Finder cells = find.descendant(
      of: find.byType(PuzzleBoardView),
      matching: find.byType(GestureDetector),
    );

    for (int row = 0; row < size; row++) {
      for (int col = 0; col < size; col++) {
        if (!_isTypeable(board, Cell(row: row, col: col))) {
          continue;
        }
        await tester.tap(cells.at(row * size + col));
        await tester.pump();
        await tester.tap(find.byWidgetPredicate((Widget w) =>
            w is KeypadKeyView && w.data.id == '${solution[row][col]}'));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();

    expect(find.byType(PuzzleScreen), findsNothing,
        reason: 'a solved board should end the session');
    expect(find.text('¡Lo armaste!'), findsOneWidget,
        reason: 'solving ends the session on a screen that did not exist when '
            'this case was written, which is why it expected the home '
            'directly; nothing ran it, so nothing said so');

    await tester.tap(find.text('Seguir'));
    for (int i = 0; i < 20 && find.byType(HomeScreen).evaluate().isEmpty; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('every format the pack carries opens from the home',
      (WidgetTester tester) async {
    await launchOnTheHome(tester);

    final List<String> names = tester
        .widget<HomeScreen>(find.byType(HomeScreen))
        .puzzles
        .map((PuzzleOption option) => option.label)
        .toList();
    expect(
      names,
      isNotEmpty,
      reason: 'PROC-10: a pack that lost its puzzles would make the loop below '
          'vacuous and the whole case would pass by walking nothing',
    );
    expect(names, hasLength(5), reason: 'the shipped pack carries five formats');

    for (final String name in names) {
      await tester.ensureVisible(find.text(name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      for (int i = 0; i < 20 && !_onABoard(); i++) {
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }
      expect(_onABoard(), isTrue, reason: '$name did not open');
      _expectItsConstraintsDrawn(tester, name);

      await tester.tap(_theWayOutOfABoard);
      for (int i = 0; i < 20 && find.byType(HomeScreen).evaluate().isEmpty; i++) {
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
      }
      expect(find.byType(HomeScreen), findsOneWidget, reason: 'stuck after $name');
    }
  });
}

/// Whether [cell] is one the player can type into.
///
/// A cell the board already supplies is not typeable, and tapping one and then
/// pressing a digit is how a filled board ends up rejected.
bool _isTypeable(PuzzleBoard board, Cell cell) =>
    !board.given.contains(cell) && !board.blocked.contains(cell);

/// The control that leaves a full-screen board.
///
/// **Out through `Salir`, not `pageBack`.** A puzzle is pushed full-screen with
/// no navigation affordance — that is the design — so there is no
/// `CupertinoNavigationBarBackButton` for the harness to press. Both board
/// screens carry the same labelled control, which is the one route a player
/// actually has.
///
/// **Matched on the `Semantics` widget rather than through `bySemanticsLabel`**,
/// which reads the compiled semantics tree and needs it switched on. The widget
/// is there either way, and it is the thing the label is attached to.
final Finder _theWayOutOfABoard = find.byWidgetPredicate(
  (Widget w) => w is Semantics && w.properties.label == 'Salir',
  description: 'the way out of a full-screen board',
);

/// The board is showing what its format asks of the player.
///
/// **`_onABoard` says a screen opened; this says its constraints reached it.**
/// A format wired up wrongly draws a grid and nothing else, opens from the home
/// and comes back — which is what the widget-level *five kinds reachable* gate
/// cannot see either. Each assertion is on a mark only that format's
/// constraints produce: a cage outline is a painter no other format installs,
/// and a Kakuro's clue carries an arrow no cell value has.
///
/// **The magic square is asked for every one of its targets, not one of them.**
/// This said the target is `n(n² + 1) / 2` and therefore larger than any cell —
/// **which is false of the shipped boards**, whose lines carry their own totals
/// rather than the classic constant: the day's are `[9, 20, 16]`, and a `9` on
/// a board whose cells hold 1 to `size²` could be a given. Six numbers all
/// present at once is something only the margin draws. Measured with a probe
/// over the shipped pack rather than reasoned about a second time.
///
/// **Switched over the leaves**, so a sixth format is a compile error in the
/// tour as well as in `boardConstraints` — the same construction, held at the
/// one place where the puzzle is the shipped pack's rather than a fixture's.
void _expectItsConstraintsDrawn(WidgetTester tester, String name) {
  final Finder screen = find.byType(PuzzleScreen);
  if (screen.evaluate().isEmpty) {
    expect(
      find.byType(WordSearchScreen),
      findsOneWidget,
      reason: '$name: the sopa de letras is letters and a word list, so it has '
          'no board and asks nothing of one',
    );
    return;
  }
  final Finder board = find.byType(PuzzleBoardView);
  Finder onBoard(String text) =>
      find.descendant(of: board, matching: find.text(text));
  final Finder cageOutlines = find.descendant(
    of: board,
    matching: find.byWidgetPredicate(
      (Widget w) => w is CustomPaint && w.foregroundPainter is CageEdgePainter,
    ),
  );

  /// Every outline the board's cage painters were actually handed.
  ///
  /// **This is where the data is genuine.** Every other assertion about a
  /// Killer cage is made against a puzzle a test constructor built; these are
  /// the shipped pack's seven, opened from the home on a real device.
  Set<CageOutline> outlinesDrawn() => cageOutlines
      .evaluate()
      .map((Element e) => (e.widget as CustomPaint).foregroundPainter)
      .whereType<CageEdgePainter>()
      .map((CageEdgePainter painter) => painter.outline)
      .toSet();

  switch (tester.widget<PuzzleScreen>(screen).puzzle) {
    case KenKenPuzzle():
      expect(cageOutlines, findsWidgets, reason: '$name drew no cage');
      expect(outlinesDrawn(), <CageOutline>{CageOutline.kenKen},
          reason: '$name drew a cage in another format\'s outline');
    case KillerPuzzle():
      expect(cageOutlines, findsWidgets, reason: '$name drew no cage');
      expect(outlinesDrawn(), <CageOutline>{CageOutline.killer},
          reason: '$name drew KenKen\'s dash — the defect this tour could not '
              'see, because a cage was drawn so findsWidgets passed, and it '
              'was KenKen\'s 6 4 on all seven of the pack\'s Killer boards');
    case MagicSquarePuzzle(
        :final List<int> rowTargets,
        :final List<int> columnTargets,
      ):
      for (final int total in <int>[...rowTargets, ...columnTargets]) {
        expect(onBoard('$total'), findsWidgets,
            reason: '$name is missing the line total $total');
      }
    case KakuroPuzzle(:final List<Run> runs):
      final Run run = runs.first;
      expect(onBoard('${run.sum}${run.isAcross ? '→' : '↓'}'), findsWidgets,
          reason: '$name drew no clue');
  }
}

/// Whether a board of either kind is on screen.
///
/// Two screens, because the sopa de letras has no keypad and therefore no
/// `PuzzleScreen`: its drag is resolved by `letterAt` rather than by a detector
/// per cell, which is why it did not fit the shared one.
bool _onABoard() =>
    find.byType(PuzzleScreen).evaluate().isNotEmpty ||
    find.byType(WordSearchScreen).evaluate().isNotEmpty;
