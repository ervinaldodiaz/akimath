import 'package:flutter/widgets.dart';

import '../../../content/model/puzzle.dart';
import '../../../design/puzzle/cage_edge_painter.dart';
import '../../../design/puzzle/spec/board_geometry.dart';
import '../../../design/puzzle/spec/cage_outline.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/candy_surface.dart';
import '../../../design/widgets/spec/puzzle_cell_visual.dart';
import '../policy/board_constraints.dart';
import '../policy/puzzle_entry.dart';

/// The grid: cells, cage outlines and the targets they carry.
///
/// **It constructs no geometry.** Cell rectangles, cage borders and label
/// anchors all come from `board_geometry.dart` — `no_geometry_literal_test`
/// scans this directory for `Offset(`, and a grid is nothing but offsets. What
/// is here is the reading of those numbers into widgets.
///
/// **It never draws a value the player has not entered.** The solution rides
/// along on the device because grading has to work with no server; a cell that
/// showed what it was hiding would give the board away, so
/// `puzzle_board_test.dart` sweeps for exactly that.
class PuzzleBoardView extends StatelessWidget {
  const PuzzleBoardView({
    super.key,
    required this.entry,
    required this.constraints,
    required this.onTapCell,
  });

  final PuzzleEntry entry;

  /// What this format puts on the board — cages, line totals or run sums.
  ///
  /// **One argument, decided once**, by `boardConstraints`. It was four lists
  /// assembled at the call site from four wildcard switches, which is how a
  /// format could be drawn with its constraints missing and nothing say so.
  final BoardConstraints constraints;

  final ValueChanged<Cell> onTapCell;

  @override
  Widget build(BuildContext context) {
    return constraints.hasLineTargets ? _gridInsideItsMargins() : _grid();
  }

  /// The grid with a line of targets down its right and along its bottom.
  ///
  /// **Only the formats with totals to show make room for them**, so a magic
  /// square and a KenKen draw the same grid at the same size and only one has
  /// labels beside it. The margin is space *around* an unchanged square:
  /// `cellRect` is untouched and the grid keeps the size it would have had.
  ///
  /// **`IntrinsicHeight`**, so the row-target column has a height to divide.
  /// Without it the margin's `Expanded`s are handed unbounded height — the
  /// grid's height comes from its own aspect ratio, which the row does not know
  /// until it has laid the grid out.
  Widget _gridInsideItsMargins() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: _grid()),
              _margin(constraints.rowTargets, vertical: true),
            ],
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(child: _margin(constraints.columnTargets, vertical: false)),
            const SizedBox(width: _marginExtent),
          ],
        ),
      ],
    );
  }

  /// How much room a line of targets takes.
  static const double _marginExtent = 28;

  /// The targets down the right or along the bottom.
  Widget _margin(List<int> targets, {required bool vertical}) {
    final List<Widget> labels = <Widget>[
      for (final int target in targets)
        Expanded(
          child: Center(
            child: Text('$target', style: BrandText.eyebrow(size: 11)),
          ),
        ),
    ];
    return SizedBox(
      width: vertical ? _marginExtent : null,
      height: vertical ? null : _marginExtent,
      child: vertical
          ? Column(children: labels)
          : Row(children: labels),
    );
  }

  /// The board, framed.
  ///
  /// **The thick ink outline is the board's and nothing else's.**
  /// `reactivos-puzzles.md`: *"El contorno grueso se reserva para el objeto (el
  /// tablero). Dentro, la jerarquía deja de ser grosor y pasa a ser peso, color
  /// y trazo."* Inside are a 1.5 px hairline and a dashed pink cage; the frame
  /// is what those two step down *from*, and without it the grid floated with
  /// no object boundary at all.
  Widget _grid() {
    return AspectRatio(
      aspectRatio: 1,
      child: CandySurface(
        borderRadius: BrandShape.radiusCardMedium,
        padding: const EdgeInsets.all(_insetClearingTheCornerArc),
        clip: true,
        child: _cells(),
      ),
    );
  }

  /// How far the grid stands back from the frame around it.
  ///
  /// **A square grid does not fit a rounded rectangle.** Flush to the frame,
  /// each corner arc cut across the outermost cells: a curved ink line crossing
  /// straight pink dashes, and a cage that appeared to run off the board. A
  /// 26 px radius intrudes about `26 × (1 − 1/√2)` ≈ 8 px on the diagonal, so
  /// `space2` is the smallest inset that clears it — and the gap it leaves is
  /// what makes the frame read as the object holding the grid rather than as
  /// its outermost line.
  static const double _insetClearingTheCornerArc = BrandShape.space2;

  /// The cells, on a square sized by the narrower axis of whatever this is
  /// given — the same rule `cellRect` follows, so the two cannot disagree about
  /// how big a cell is.
  ///
  /// The builder's box is named `available` rather than `constraints`: this
  /// widget's own [constraints] are the format's, and a `BoxConstraints` called
  /// the same thing shadows them, which is what the analyzer said the first
  /// time this was written.
  Widget _cells() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints available) {
          final double side = available.biggest.shortestSide;
          final Rect box = Rect.fromLTWH(0, 0, side, side);
          final Map<Cell, Cage> cageOf = <Cell, Cage>{
            for (final Cage cage in constraints.cages)
              for (final Cell cell in cage.cells) cell: cage,
          };

          return SizedBox(
            width: side,
            height: side,
            child: Stack(
              children: <Widget>[
                for (int row = 0; row < entry.board.size; row++)
                  for (int col = 0; col < entry.board.size; col++)
                    _positioned(box, row, col, cageOf),
              ],
            ),
          );
      },
    );
  }

  /// The clues a cell begins, if any.
  ///
  /// **Anchored to the run's own first cell** rather than a preceding blocked
  /// cell (design D2). Newspaper Kakuro splits the two sums into the black
  /// square before a run; the frozen format does not promise one exists — the
  /// golden fixture has a run starting at column 0 with nothing to its left.
  ///
  /// A cell may begin both an across and a down run, and both are shown: one
  /// that hid the other would hide a constraint the player needs.
  ({String? across, String? down}) _cluesAt(Cell cell) {
    String? across;
    String? down;
    for (final Run run in constraints.runs) {
      if (run.cells.first != cell) {
        continue;
      }
      if (run.isAcross) {
        across = '${run.sum}';
      } else {
        down = '${run.sum}';
      }
    }
    return (across: across, down: down);
  }

  /// One cell, placed where `cellRect` puts it.
  ///
  /// **The outline arrives rather than being chosen here.** Naming a `DashSpec`
  /// on this line is what made a Killer board draw the KenKen dash: the widget
  /// serves five formats and had no way to know which one it was drawing.
  /// `BoardConstraints.cages` hands the cages and their outline down together.
  Widget _positioned(Rect box, int row, int col, Map<Cell, Cage> cageOf) {
    final Cell cell = Cell(row: row, col: col);
    final Rect rect =
        cellRect(GridCell(row, col), size: entry.board.size, box: box);
    final Cage? cage = cageOf[cell];

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: _Cell(
        cell: cell,
        entry: entry,
        edges: cage == null ? null : _edgesFor(cage, cell),
        outline: constraints.outline,
        target: cage != null && _isAnchor(cage, cell) ? _label(cage) : null,
        clues: _cluesAt(cell),
        onTap: () => onTapCell(cell),
      ),
    );
  }

  /// What a cage's corner says.
  ///
  /// The target always; the operation only when the format named one and there
  /// is more than one cell to combine. A Killer cage asks for a sum and says so
  /// by saying nothing, and `3+` on a single cell is not a sum in any format.
  String _label(Cage cage) {
    final String? operation = cage.operation;
    if (operation == null || cage.cells.length == 1) {
      return '${cage.target}';
    }
    return '${cage.target}$operation';
  }

  CageEdges? _edgesFor(Cage cage, Cell cell) {
    final Set<GridCell> cells = <GridCell>{
      for (final Cell c in cage.cells) GridCell(c.row, c.col),
    };
    for (final CageEdges edges in cageEdges(cells)) {
      if (edges.cell.row == cell.row && edges.cell.col == cell.col) {
        return edges;
      }
    }
    return null;
  }

  /// Whether this is the cell a cage hangs its target on.
  ///
  /// Only the anchor carries it, so a five-cell cage shows its sum once rather
  /// than five times.
  bool _isAnchor(Cage cage, Cell cell) {
    final GridCell anchor = cageLabelAnchor(<GridCell>{
      for (final Cell c in cage.cells) GridCell(c.row, c.col),
    });
    return anchor.row == cell.row && anchor.col == cell.col;
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.cell,
    required this.entry,
    required this.edges,
    required this.outline,
    required this.target,
    required this.clues,
    required this.onTap,
  });

  final Cell cell;
  final PuzzleEntry entry;
  final CageEdges? edges;

  /// How a cage is drawn on this board. Non-null whenever [edges] is, because
  /// `BoardConstraints.cages` cannot be built without one.
  final CageOutline? outline;

  final String? target;

  /// The run sums this cell begins, along and down.
  ///
  /// Across is drawn at the top and down at the bottom-left — the directions
  /// they read in, so the pairing needs no legend.
  final ({String? across, String? down}) clues;

  final VoidCallback onTap;

  PuzzleCellKind get _kind {
    if (entry.board.blocked.contains(cell)) return PuzzleCellKind.blocked;
    if (entry.board.given.contains(cell)) return PuzzleCellKind.given;
    return PuzzleCellKind.open;
  }

  @override
  Widget build(BuildContext context) {
    final bool selected = entry.selected == cell;
    final PuzzleCellVisual visual = resolvePuzzleCell(_kind, selected: selected);
    final int? value = entry.valueAt(cell);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: visual.background,
          border: _gridRule(),
        ),
        child: CustomPaint(
          foregroundPainter: _cageBoundary(),
          child: Stack(
            children: <Widget>[
              if (target != null)
                Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(target!, style: BrandText.eyebrow(size: 10)),
                ),
              if (clues.across != null)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text('${clues.across}→',
                        style: BrandText.eyebrow(size: 9)),
                  ),
                ),
              if (clues.down != null)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Text('${clues.down}↓',
                        style: BrandText.eyebrow(size: 9)),
                  ),
                ),
              if (value != null)
                Center(
                  child: Text('$value', style: BrandText.numeral(22)),
                ),
              if (selected) _selectionRing(),
            ],
          ),
        ),
      ),
    );
  }

  /// The thin grid, drawn on every cell; a cage's heavier border goes over it.
  ///
  /// **A hairline, not a box.** `reactivos-puzzles.md` puts the cells at 1.5 px
  /// ink-18% and reserves weight for the board itself; at `muted` and 2 px the
  /// grid competed with everything drawn on it.
  Border _gridRule() => Border.all(
        color: BrandColors.gridHairline,
        width: BrandShape.borderWidthHairline,
      );

  /// The cage boundary crossing this cell, where one does.
  ///
  /// **Dashed pink, not solid ink.** The thick ink outline is the board's, and
  /// a cage drawn in it read as a second object stacked on the first — on a
  /// board where most cells touch a boundary, that is most of the grid in the
  /// heaviest stroke the app has. Which dash and which stroke is
  /// `cage_outline.dart`'s to say, not this widget's.
  CustomPainter? _cageBoundary() {
    final CageEdges? boundary = edges;
    final CageOutline? cage = outline;
    if (boundary == null || cage == null) {
      return null;
    }
    return CageEdgePainter(edges: boundary, outline: cage);
  }

  /// The mark on the cell the player is looking at.
  ///
  /// **The ring is inset, and the fill does the shouting.** Drawn flush it
  /// landed exactly on the cage's outline — same ink, same 3 px — so a cell
  /// enclosed by its cage showed no selection at all. The inset makes it a
  /// second line a player can see beside the first, and it is still a *shape*
  /// difference, which is what BRD-1 asks of a state a reader cannot get by hue.
  Widget _selectionRing() {
    return Padding(
      padding: const EdgeInsets.all(BrandShape.borderWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: BrandColors.ink,
            width: BrandShape.borderWidth,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
