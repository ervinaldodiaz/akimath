import 'package:flutter/material.dart';

import '../../../content/model/puzzle.dart';
import '../../../design/icons/brand_icon.dart';
import '../../../design/puzzle/cage_edge_painter.dart';
import '../../../design/puzzle/spec/board_geometry.dart';
import '../../../design/puzzle/spec/cage_outline.dart';
import '../../../design/tokens/tokens.dart';
import '../../../design/widgets/brand_button.dart';
import '../../../design/widgets/candy_surface.dart';
import '../../../design/widgets/icon_button_tile.dart';
import '../../../design/widgets/spec/puzzle_cell_visual.dart';
import '../policy/reference_card.dart';

/// `Hoja de referencia` — a titled card a player glances at mid-board.
///
/// **The rules are the pack's** (`referenceRows`), which is what lets a sixth
/// format arrive as content. The pictures beside them are the format's, drawn
/// here, because a diagram is geometry and geometry has no business travelling
/// through the offline pack.
///
/// **The band of rules scrolls and the frame does not.** The design draws a
/// fixed card holding three 84px rows, two rules and a button; at `textScaler`
/// 1.3 on the notched viewport that is over the height a screen gets, and the
/// frozen schema admits six lines rather than three. The title and the way out
/// stay put — those are the two things a player who opened this by accident is
/// looking for.
class ReferenceCard extends StatelessWidget {
  const ReferenceCard({
    super.key,
    required this.puzzle,
    required this.onClose,
  });

  final Puzzle puzzle;

  /// Back to the board. Both ways out call it.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final List<ReferenceRow> rows = referenceRows(puzzle);
    return CandySurface(
      padding: const EdgeInsets.all(BrandShape.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _heading(),
          const SizedBox(height: BrandShape.space3),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final ReferenceRow row in rows) _RuleRow(row: row),
                ],
              ),
            ),
          ),
          const SizedBox(height: BrandShape.space3),
          BrandButton.primary(label: 'Volver al tablero', onPressed: onClose),
        ],
      ),
    );
  }

  Widget _heading() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            referenceCardTitle(puzzle),
            style: BrandText.cardTitle(size: 22),
          ),
        ),
        const SizedBox(width: BrandShape.space2),
        _closeControl(),
      ],
    );
  }

  /// The way out in the corner of the card.
  ///
  /// **Labelled**, because a glyph-only control says nothing to a screen reader
  /// — the same rule the board's own way out follows.
  Widget _closeControl() {
    return Semantics(
      label: 'Cerrar la hoja',
      button: true,
      child: IconButtonTile(
        onPressed: onClose,
        child: const BrandIcon(BrandGlyph.close, size: 18),
      ),
    );
  }
}

/// One rule: its picture, then its words.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.row});

  final ReferenceRow row;

  @override
  Widget build(BuildContext context) {
    final ReferenceDiagram? diagram = row.diagram;
    return Padding(
      padding: const EdgeInsets.only(bottom: BrandShape.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (diagram != null) ...<Widget>[
            ReferenceDiagramView(diagram: diagram),
            const SizedBox(width: BrandShape.space3),
          ],
          Expanded(child: _words()),
        ],
      ),
    );
  }

  /// The rule itself, in ink rather than `caption`'s muted default: this is the
  /// content of the card, not a note beside it.
  Widget _words() {
    return Text(
      row.text,
      style: BrandText.caption(
        size: 14,
        color: BrandColors.ink,
        height: 1.45,
      ),
    );
  }
}

/// A miniature board, drawn from the data the policy chose.
///
/// **It constructs no geometry**, for the reason `PuzzleBoardView` gives:
/// `no_geometry_literal_test` scans this directory for `Offset(`, and the cage
/// outline comes from `cageEdges` in `design/puzzle/spec/`. Nothing here is
/// pressable, so it is not a touch target and the 48px floor does not apply —
/// which is why a real board cannot be shrunk into this slot.
class ReferenceDiagramView extends StatelessWidget {
  const ReferenceDiagramView({super.key, required this.diagram});

  final ReferenceDiagram diagram;

  /// The design draws the diagram beside a rule at 84 square.
  static const double _side = 76;

  @override
  Widget build(BuildContext context) {
    final Set<GridCell> cage = <GridCell>{
      for (final int index in diagram.cage)
        GridCell(index ~/ diagram.size, index % diagram.size),
    };
    final List<CageEdges> outline = cageEdges(cage);
    final GridCell? anchor = cage.isEmpty ? null : cageLabelAnchor(cage);

    return ExcludeSemantics(
      child: CandySurface(
        width: _side,
        height: _side,
        borderRadius: BrandShape.radiusControl,
        shadowOffset: BrandShape.shadowPill,
        clip: true,
        child: Column(
          children: <Widget>[
            for (int row = 0; row < diagram.size; row++)
              Expanded(
                child: Row(
                  children: <Widget>[
                    for (int col = 0; col < diagram.size; col++)
                      Expanded(
                        child: _DiagramCell(
                          diagram: diagram,
                          index: row * diagram.size + col,
                          edges: _edgesAt(outline, row, col),
                          carriesCageLabel:
                              anchor != null && anchor.row == row && anchor.col == col,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  CageEdges? _edgesAt(List<CageEdges> outline, int row, int col) {
    for (final CageEdges edges in outline) {
      if (edges.cell.row == row && edges.cell.col == col) {
        return edges;
      }
    }
    return null;
  }
}

/// One cell of a miniature.
///
/// It takes **the board's own cell fills** from `resolvePuzzleCell`, so the
/// picture and the thing it is about are the same colours — a diagram that
/// invented its own would be teaching a board the player is not looking at.
class _DiagramCell extends StatelessWidget {
  const _DiagramCell({
    required this.diagram,
    required this.index,
    required this.edges,
    required this.carriesCageLabel,
  });

  final ReferenceDiagram diagram;
  final int index;
  final CageEdges? edges;
  final bool carriesCageLabel;

  PuzzleCellKind get _kind {
    if (diagram.shaded.contains(index)) return PuzzleCellKind.blocked;
    if (diagram.highlighted.contains(index)) return PuzzleCellKind.given;
    return PuzzleCellKind.open;
  }

  /// The cage boundary crossing this cell, where one does.
  ///
  /// The diagram's own format, stepped down to the hairline it rules its cells
  /// with — the picture teaches the board the player is looking at, so a KenKen
  /// rule shows KenKen's dash and a Killer rule shows the dots.
  CustomPainter? _cageBoundary() {
    final CageEdges? boundary = edges;
    final CageOutline? cage = diagram.cageOutline;
    if (boundary == null || cage == null) {
      return null;
    }
    return CageEdgePainter(edges: boundary, outline: cage.miniature);
  }

  @override
  Widget build(BuildContext context) {
    final PuzzleCellVisual visual = resolvePuzzleCell(_kind, selected: false);
    final String? label = diagram.labels[index];
    final String? cageLabel = diagram.cageLabel;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: visual.background,
        border: Border.all(
          color: BrandColors.gridHairline,
          width: BrandShape.borderWidthHairline,
        ),
      ),
      child: CustomPaint(
        foregroundPainter: _cageBoundary(),
        child: Stack(
          children: <Widget>[
            if (label != null)
              Center(child: Text(label, style: BrandText.eyebrow(size: 9))),
            if (carriesCageLabel && cageLabel != null)
              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  cageLabel,
                  style: BrandText.eyebrow(size: 8, color: BrandColors.pink),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
