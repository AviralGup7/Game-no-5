/// The board: clue strips plus the grid, drawn in one CustomPainter.
///
/// Layout problem specific to nonograms: the clues live OUTSIDE the grid, on
/// the top and left, and the strips must be wide enough for the longest clue
/// list on that axis. Sizing them off the longest list rather than a fixed
/// guess is what keeps a 12x12 readable without shrinking the cells.
///
/// Accessibility decisions baked in here:
///   * Cells are as large as the screen allows, and never below 34 logical
///     pixels even on a 12x12 on a small phone.
///   * A filled square is a near-solid block, not a tint.
///   * A crossed-out square is an X in a DIFFERENT HUE, so the two states are
///     distinguishable without relying on colour alone.
///   * A mistake gets a red X/underline AND is shaken by the caller — never
///     colour by itself.
///   * Finished clue lines grey out, the way you would tick them on paper.
///   * Drag to paint: dragging applies the current tool to every square you
///     cross. Tapping 60 squares one at a time is what makes big grids
///     unpleasant, and precise repeated tapping is exactly what arthritic
///     hands struggle with.
library;

import 'package:flutter/material.dart';
import '../engine/nonogram_engine.dart';
import '../models/game_state.dart';
import 'app_theme.dart';

class NonogramBoard extends StatefulWidget {
  final GameState game;
  final double fontScale;
  final bool highContrast;
  final bool highlightLine;
  final bool showMistakes;

  /// Cell the last hint pointed at, flashed so it can be found.
  final int? hintIndex;

  /// Called with the index of a cell the player wants to change.
  final void Function(int index) onCell;

  /// Called when a drag paints across cells, with the cells it crossed.
  final void Function(int index, int mark)? onPaint;

  const NonogramBoard({
    super.key,
    required this.game,
    required this.onCell,
    this.onPaint,
    this.fontScale = 1.0,
    this.highContrast = false,
    this.highlightLine = true,
    this.showMistakes = true,
    this.hintIndex,
  });

  @override
  State<NonogramBoard> createState() => _NonogramBoardState();
}

class _NonogramBoardState extends State<NonogramBoard> {
  /// Cells already painted during the CURRENT drag, so dragging back and forth
  /// over one square does not toggle it repeatedly.
  final Set<int> _strokeDone = {};
  int? _strokeMark;
  _Metrics? _metrics;

  void _handleAt(Offset local, {required bool isDrag}) {
    final m = _metrics;
    if (m == null) return;
    final i = m.cellAt(local);
    if (i == null) return;

    if (!isDrag) {
      widget.onCell(i);
      // Whatever the tap produced becomes the mark the rest of the drag paints,
      // so a drag is always uniform instead of alternating on/off.
      _strokeMark = widget.game.marks[i];
      _strokeDone
        ..clear()
        ..add(i);
      return;
    }

    if (_strokeDone.contains(i)) return;
    _strokeDone.add(i);
    final mark = _strokeMark;
    if (mark == null || widget.onPaint == null) return;
    widget.onPaint!(i, mark);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final m = _Metrics.fit(
          puzzle: widget.game.puzzle,
          available: Size(box.maxWidth, box.maxHeight),
          fontScale: widget.fontScale,
        );
        _metrics = m;

        return Semantics(
          label: 'Puzzle grid, ${widget.game.puzzle.width} by '
              '${widget.game.puzzle.height}. '
              '${widget.game.remaining} squares left to fill.',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _handleAt(d.localPosition, isDrag: false),
            onPanStart: (d) => _handleAt(d.localPosition, isDrag: false),
            onPanUpdate: (d) => _handleAt(d.localPosition, isDrag: true),
            onPanEnd: (_) {
              _strokeDone.clear();
              _strokeMark = null;
            },
            child: CustomPaint(
              size: Size(m.totalWidth, m.totalHeight),
              painter: _BoardPainter(
                game: widget.game,
                metrics: m,
                scheme: scheme,
                highContrast: widget.highContrast,
                highlightLine: widget.highlightLine,
                showMistakes: widget.showMistakes,
                hintIndex: widget.hintIndex,
                fontScale: widget.fontScale,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Everything about where things are drawn, computed once per layout.
class _Metrics {
  final Puzzle puzzle;
  final double cell;
  final double clueLeft;
  final double clueTop;

  const _Metrics({
    required this.puzzle,
    required this.cell,
    required this.clueLeft,
    required this.clueTop,
  });

  double get gridWidth => cell * puzzle.width;
  double get gridHeight => cell * puzzle.height;
  double get totalWidth => clueLeft + gridWidth;
  double get totalHeight => clueTop + gridHeight;

  /// Which cell contains [p], or null if the touch landed on a clue strip.
  int? cellAt(Offset p) {
    final x = p.dx - clueLeft;
    final y = p.dy - clueTop;
    if (x < 0 || y < 0) return null;
    final c = (x / cell).floor();
    final r = (y / cell).floor();
    if (c < 0 || c >= puzzle.width || r < 0 || r >= puzzle.height) return null;
    return r * puzzle.width + c;
  }

  static _Metrics fit({
    required Puzzle puzzle,
    required Size available,
    required double fontScale,
  }) {
    // Strips are sized off the LONGEST clue list on each axis. A fixed guess
    // either wastes space on easy boards or clips numbers on hard ones.
    final maxRowClues =
        puzzle.rowClues.fold<int>(1, (a, l) => l.length > a ? l.length : a);
    final maxColClues =
        puzzle.colClues.fold<int>(1, (a, l) => l.length > a ? l.length : a);

    // Solve for the cell size that makes the whole thing fit both axes.
    // Clue text is sized relative to the cell, so the strips scale with it.
    const clueUnitRatio = 0.62;
    final wDen = puzzle.width + maxRowClues * clueUnitRatio;
    final hDen = puzzle.height + maxColClues * clueUnitRatio;

    var cell = (available.width / wDen);
    final byHeight = available.height / hDen;
    if (byHeight < cell) cell = byHeight;

    // Never let a cell get too small to hit reliably, even if that means the
    // board scrolls. 34dp is below the 56dp guidance for buttons, but a grid
    // cell is a different target: it is surrounded by its own kind, and the
    // drag-to-paint gesture makes precision less critical.
    if (cell < 34) cell = 34;
    if (cell > 74) cell = 74;

    return _Metrics(
      puzzle: puzzle,
      cell: cell,
      clueLeft: maxRowClues * cell * clueUnitRatio,
      clueTop: maxColClues * cell * clueUnitRatio,
    );
  }
}

class _BoardPainter extends CustomPainter {
  final GameState game;
  final _Metrics metrics;
  final ColorScheme scheme;
  final bool highContrast;
  final bool highlightLine;
  final bool showMistakes;
  final int? hintIndex;
  final double fontScale;

  _BoardPainter({
    required this.game,
    required this.metrics,
    required this.scheme,
    required this.highContrast,
    required this.highlightLine,
    required this.showMistakes,
    required this.hintIndex,
    required this.fontScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = game.puzzle;
    final m = metrics;
    final cell = m.cell;

    final selRow = game.selected >= 0 ? p.rowOf(game.selected) : -1;
    final selCol = game.selected >= 0 ? p.colOf(game.selected) : -1;

    // ---- highlight the line under the finger, before anything is drawn on top
    if (highlightLine && game.selected >= 0) {
      final wash = Paint()..color = AppTheme.peerFill(scheme);
      canvas.drawRect(
          Rect.fromLTWH(0, m.clueTop + selRow * cell, m.totalWidth, cell), wash);
      canvas.drawRect(
          Rect.fromLTWH(m.clueLeft + selCol * cell, 0, cell, m.totalHeight),
          wash);
    }

    // ---- cells
    final painted = Paint()..color = AppTheme.paintedCell(scheme);
    final givenPainted = Paint()
      ..color = AppTheme.paintedCell(scheme).withValues(alpha: .78);

    for (var r = 0; r < p.height; r++) {
      for (var c = 0; c < p.width; c++) {
        final i = r * p.width + c;
        final rect = Rect.fromLTWH(
            m.clueLeft + c * cell, m.clueTop + r * cell, cell, cell);
        final mark = game.marks[i];
        final wrong = showMistakes && game.isWrong(i);

        if (i == hintIndex) {
          canvas.drawRect(rect.deflate(1), Paint()..color = AppTheme.hintFill(scheme));
        }

        if (mark == kMarkFilled) {
          // A given is drawn slightly softer so the player can tell what was
          // handed to them from what they worked out.
          canvas.drawRect(rect.deflate(cell * 0.06),
              game.isGiven(i) ? givenPainted : painted);
        } else if (mark == kMarkEmpty) {
          _drawCross(canvas, rect, cell, wrong);
        }

        if (wrong) {
          // Colour AND a shape: a red box plus, for a wrong fill, a slash.
          final err = Paint()
            ..color = AppTheme.wrongText(scheme)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0;
          canvas.drawRect(rect.deflate(2), err);
        }
      }
    }

    // ---- grid lines. Every 5th line is heavier: counting to 5 is the single
    // most common physical action in a nonogram, and unbroken 1px lines make
    // it error-prone.
    final thin = Paint()
      ..color = scheme.outline.withValues(alpha: highContrast ? .85 : .40)
      ..strokeWidth = highContrast ? 1.6 : 1.0;
    final thick = Paint()
      ..color = scheme.outline.withValues(alpha: highContrast ? 1 : .85)
      ..strokeWidth = highContrast ? 3.2 : 2.4;

    for (var c = 0; c <= p.width; c++) {
      final x = m.clueLeft + c * cell;
      final heavy = c % 5 == 0 || c == p.width;
      canvas.drawLine(Offset(x, heavy ? 0 : m.clueTop), Offset(x, m.totalHeight),
          heavy ? thick : thin);
    }
    for (var r = 0; r <= p.height; r++) {
      final y = m.clueTop + r * cell;
      final heavy = r % 5 == 0 || r == p.height;
      canvas.drawLine(Offset(heavy ? 0 : m.clueLeft, y), Offset(m.totalWidth, y),
          heavy ? thick : thin);
    }

    // ---- clues
    final clueSize = (cell * 0.42).clamp(11.0, 26.0);
    for (var r = 0; r < p.height; r++) {
      final done = game.isRowComplete(r);
      final clues = p.rowClues[r];
      for (var k = 0; k < clues.length; k++) {
        // Right-aligned against the grid, so the last number always sits next
        // to the row it describes.
        final slot = clues.length - k;
        _text(
          canvas,
          '${clues[k]}',
          Offset(m.clueLeft - (slot - 0.5) * cell * 0.62,
              m.clueTop + r * cell + cell / 2),
          clueSize,
          done ? AppTheme.doneClue(scheme) : scheme.onSurface,
          bold: !done,
        );
      }
    }
    for (var c = 0; c < p.width; c++) {
      final done = game.isColComplete(c);
      final clues = p.colClues[c];
      for (var k = 0; k < clues.length; k++) {
        final slot = clues.length - k;
        _text(
          canvas,
          '${clues[k]}',
          Offset(m.clueLeft + c * cell + cell / 2,
              m.clueTop - (slot - 0.5) * cell * 0.62),
          clueSize,
          done ? AppTheme.doneClue(scheme) : scheme.onSurface,
          bold: !done,
        );
      }
    }
  }

  void _drawCross(Canvas canvas, Rect rect, double cell, bool wrong) {
    final pad = cell * 0.28;
    final paint = Paint()
      ..color = wrong
          ? AppTheme.wrongText(scheme)
          : AppTheme.crossColour(scheme)
      ..strokeWidth = (cell * 0.10).clamp(2.0, 5.0)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(rect.topLeft + Offset(pad, pad),
        rect.bottomRight - Offset(pad, pad), paint);
    canvas.drawLine(rect.topRight + Offset(-pad, pad),
        rect.bottomLeft + Offset(pad, -pad), paint);
  }

  void _text(Canvas canvas, String s, Offset centre, double size, Color colour,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: colour,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          // Tabular figures keep columns of clues aligned.
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  /// Always repaints.
  ///
  /// GameState is mutated IN PLACE, so `old.game != game` is false even when
  /// every square has changed - a field-by-field comparison here would be
  /// worse than useless, because it would look correct while silently
  /// freezing the board. The board only repaints when its parent calls
  /// setState, which happens on a real change, so this is cheap in practice.
  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
