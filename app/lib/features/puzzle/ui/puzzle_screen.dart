import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../../content/model/puzzle.dart';
import '../../../design/icons/brand_icon.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/icon_button_tile.dart';
import '../../../design/widgets/keypad.dart';
import '../../../design/widgets/spec/keypad_layout.dart';
import '../policy/board_constraints.dart';
import '../policy/pause.dart';
import '../policy/puzzle_entry.dart';
import '../policy/reference_card.dart';
import 'paused_board.dart';
import 'puzzle_board_view.dart';
import 'reference_card.dart';

/// A KenKen, played.
///
/// The board, the 5×2 pad that has existed since F0 and been wired to nothing,
/// and one way out. It holds the entry and nothing else — what a tap or a digit
/// means is `PuzzleEntry`'s, which is why all of that is tested without pumping
/// a screen.
///
/// **The reference sheet travels with the puzzle** and is shown on demand
/// rather than on arrival: the rules of a KenKen are three lines, and three
/// lines in front of a board is a wall between a player and the thing they came
/// for. Opened, it is `Hoja de referencia` — a titled card *over* the
/// board rather than a paragraph pushed in above it, which is what the design
/// draws and what keeps the grid from resizing under a player's hand.
class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({
    super.key,
    required this.puzzle,
    this.onClose,
    this.onSolved,
    this.onPractised,
  });

  /// Any puzzle played on the shared square. A word search is not one, and the
  /// type says so rather than a getter throwing.
  final BoardPuzzle puzzle;

  /// Leaves the puzzle. Defaults to popping, so a pushed board always has an
  /// exit even if a caller forgets to wire one — the same rule the round
  /// follows, and for the same reason: a full-screen session has no system
  /// back on iOS.
  final VoidCallback? onClose;

  /// Called once, when the last cell makes the board correct.
  ///
  /// Once, and only on the transition: a callback that fired on every keystroke
  /// after completion would push a verdict screen per digit.
  final VoidCallback? onSolved;

  /// Called once, the first time a value lands on the board.
  ///
  /// **Not on solve** (design D1): a puzzle is a longer commitment than an item,
  /// and a player who works on one for half an hour and leaves it unfinished has
  /// practised. It is the board's analogue of a round submitting an answer —
  /// which records the day right or wrong.
  ///
  /// The screen reports; the route records. It holds no store, because the two
  /// puzzle formats commit differently and the same IO decision written twice
  /// is free to diverge.
  final VoidCallback? onPractised;

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  late PuzzleEntry _entry = PuzzleEntry.of(widget.puzzle.board);
  bool _reported = false;
  bool _practised = false;

  /// Whether `Hoja de referencia` is drawn over the board.
  ///
  /// **The pad goes with the board.** A key left live under an open sheet lands
  /// a digit on a grid nobody can see — and `_apply` would report
  /// `onPractised` and `onSolved` from behind the card. The design covers the
  /// pad area too: `Hoja de referencia` runs from 150 to the bottom of the
  /// screen. Same reading as the sopa's word list.
  bool _rulesOpen = false;

  /// **In memory only.** Nothing writes a half-finished board to disk, so a
  /// pause survives leaving the screen for as long as this `State` does and no
  /// longer — which is what `PausedBoardView`'s copy says out loud rather than
  /// promising a board that comes back.
  bool _paused = false;

  void _apply(PuzzleEntry next) {
    final bool committed = _landsAValue(next);
    setState(() => _entry = next);
    if (!_practised && committed) {
      _practised = true;
      widget.onPractised?.call();
    }
    if (!_reported && next.isSolved) {
      _reported = true;
      widget.onSolved?.call();
    }
  }

  /// Whether [next] puts something **on the board**, rather than being a press.
  ///
  /// Selecting a cell, and a digit the board cannot hold, both leave `filled`
  /// alone — and neither asserts anything about the puzzle.
  bool _landsAValue(PuzzleEntry next) => !mapEquals(next.filled, _entry.filled);

  /// The digits this board cannot hold.
  ///
  /// A 3×3 KenKen admits 1 to 3, so 4 to 9 are shown unavailable rather than quietly
  /// doing nothing. `PuzzleEntry` refuses them either way — this changes what a
  /// player is invited to press, not what happens if they do.
  Set<String> get _tooLarge => <String>{
        for (int digit = widget.puzzle.board.highestValue + 1; digit <= 9; digit++)
          '$digit',
      };

  void _onKey(KeypadKey key) {
    if (key.id == 'backspace') {
      _apply(_entry.clear());
      return;
    }
    final int? value = int.tryParse(key.emits ?? '');
    if (value != null) {
      _apply(_entry.type(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_paused) {
      return PausedBoardView(
        summary: pauseSummary(widget.puzzle, _entry),
        onResume: () => setState(() => _paused = false),
        onLeave: widget.onClose ?? () => Navigator.of(context).maybePop(),
      );
    }
    return Scaffold(
      backgroundColor: BrandColors.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BrandShape.space4,
            vertical: BrandShape.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _header(),
              const SizedBox(height: BrandShape.space3),
              Expanded(
                child: _rulesOpen
                    ? ReferenceCard(
                        puzzle: widget.puzzle,
                        onClose: () => setState(() => _rulesOpen = false),
                      )
                    : Center(child: _board()),
              ),
              const SizedBox(height: BrandShape.space3),
              if (!_rulesOpen)
                Keypad(
                  layout: KeypadLayout.puzzle,
                  onKeyPressed: _onKey,
                  unavailable: _tooLarge,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The board, asked for rather than assembled.
  ///
  /// This was four `switch` expressions ending in `_ => const <…>[]`, so the
  /// screen named three formats to build one widget and a fourth format's
  /// constraints were whatever fell through. `boardConstraints` is exhaustive
  /// over the sealed hierarchy, which is what turns the sixth format from a
  /// bare grid into a compile error (`docs/solid/puzzle.md`, finding 1).
  Widget _board() {
    return PuzzleBoardView(
      entry: _entry,
      constraints: boardConstraints(widget.puzzle),
      onTapCell: (Cell cell) => _apply(_entry.select(cell)),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _exitControl(),
        _formatName(),
        _rulesControl(),
        const SizedBox(width: BrandShape.space2),
        _pauseControl(),
      ],
    );
  }

  /// The direct way out of the board.
  ///
  /// **Labelled**, because a glyph-only control says nothing to a screen reader
  /// — and a full-screen session has no system back on iOS. The pause screen
  /// offers the same exit with the cost of taking it spelled out.
  Widget _exitControl() {
    return Semantics(
      label: 'Salir',
      button: true,
      child: IconButtonTile(
        onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
        child: const BrandIcon(BrandGlyph.close, size: 22),
      ),
    );
  }

  /// What the player is playing, across the middle of the header.
  ///
  /// **Ellipsised inside an `Expanded`**, because the header carries three 48px
  /// controls once pause lands and `CUADRO MÁGICO` at `textScaler` 1.3 is wider
  /// than what is left.
  Widget _formatName() {
    return Expanded(
      child: Center(
        child: Text(
          puzzleFormatName(widget.puzzle),
          style: BrandText.eyebrow(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Opens and closes `Hoja de referencia`.
  Widget _rulesControl() {
    return Semantics(
      label: 'Cómo se juega',
      button: true,
      child: IconButtonTile(
        toggled: _rulesOpen,
        onPressed: () => setState(() => _rulesOpen = !_rulesOpen),
        child: const BrandIcon(BrandGlyph.hint, size: 22),
      ),
    );
  }

  /// Covers the board, where the design puts it: the right of its own header.
  Widget _pauseControl() {
    return Semantics(
      label: 'Pausar',
      button: true,
      child: IconButtonTile(
        onPressed: () => setState(() {
          _paused = true;
          _rulesOpen = false;
        }),
        child: const BrandIcon(BrandGlyph.pause, size: 20),
      ),
    );
  }
}
