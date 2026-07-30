/// Mutable in-progress game: marks, undo, save/resume.
///
/// PURE DART — no Flutter imports, so it unit-tests on a bare VM.
///
/// A nonogram has THREE cell states, not two, and that third state is the one
/// beginners miss. Marking a square as definitely-empty is the core technique;
/// without it you cannot keep track of what you have ruled out. So the app
/// gives "empty" its own first-class mark, its own colour, and its own button,
/// rather than treating it as "not filled yet".
library;

import 'dart:convert';
import '../engine/nonogram_engine.dart';

/// What the player has put in a square.
const int kMarkNone = -1;
const int kMarkEmpty = 0;
const int kMarkFilled = 1;

/// What tapping a square does.
enum Tool {
  /// Paint the picture.
  fill('Fill'),

  /// Rule a square out. The technique that actually solves nonograms.
  cross('Cross out');

  final String label;
  const Tool(this.label);
}

class _Move {
  final int index;
  final int before;
  final int after;
  const _Move(this.index, this.before, this.after);
}

class GameState {
  final Puzzle puzzle;

  /// One of kMarkNone / kMarkEmpty / kMarkFilled per cell.
  late List<int> marks;

  int selected = -1;
  Tool tool = Tool.fill;
  int elapsedSeconds = 0;
  int mistakes = 0;
  int hintsUsed = 0;

  final List<_Move> _undo = [];

  GameState(this.puzzle) {
    marks = List<int>.filled(puzzle.cellCount, kMarkNone);
    // Pre-revealed cells are part of the puzzle, not the player's work.
    for (final i in puzzle.givens) {
      marks[i] = puzzle.solution[i] ? kMarkFilled : kMarkEmpty;
    }
  }

  bool isGiven(int i) => puzzle.givens.contains(i);
  bool isEditable(int i) => !isGiven(i);

  /// True when every square that should be filled IS filled.
  ///
  /// Deliberately ignores crossed-out squares: a player who solved the picture
  /// but did not bother crossing everything out has finished. Demanding
  /// bookkeeping they did not need is the kind of pedantry that gets an app
  /// uninstalled.
  bool get isSolved {
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (puzzle.solution[i] && marks[i] != kMarkFilled) return false;
      // A filled mark on an empty square is a mistake, not a finish.
      if (!puzzle.solution[i] && marks[i] == kMarkFilled) return false;
    }
    return true;
  }

  int get filledCount =>
      marks.where((m) => m == kMarkFilled).length;

  /// Remaining squares to fill — shown as plain progress, never as a countdown.
  int get remaining => puzzle.filledTarget - filledCount;

  /// Apply the current tool to a square. Tapping a square that already carries
  /// that mark clears it, so one finger can both set and unset.
  ///
  /// Returns true if the move was WRONG (a fill on an empty square, or a cross
  /// on a filled one) so the UI can shake + underline it.
  bool apply(int i) {
    if (!isEditable(i)) return false;
    final want = tool == Tool.fill ? kMarkFilled : kMarkEmpty;
    final now = marks[i];
    final next = (now == want) ? kMarkNone : want;
    _push(i, next);

    if (next == kMarkNone) return false;
    final shouldFill = puzzle.solution[i];
    final wrong =
        (next == kMarkFilled && !shouldFill) || (next == kMarkEmpty && shouldFill);
    if (wrong) mistakes++;
    return wrong;
  }

  /// Directly set a mark (used by hints and by drag-painting).
  bool setMark(int i, int mark) {
    if (!isEditable(i) || marks[i] == mark) return false;
    _push(i, mark);
    if (mark == kMarkNone) return false;
    final shouldFill = puzzle.solution[i];
    final wrong =
        (mark == kMarkFilled && !shouldFill) || (mark == kMarkEmpty && shouldFill);
    if (wrong) mistakes++;
    return wrong;
  }

  void erase(int i) {
    if (!isEditable(i) || marks[i] == kMarkNone) return;
    _push(i, kMarkNone);
  }

  void _push(int i, int next) {
    _undo.add(_Move(i, marks[i], next));
    marks[i] = next;
    if (_undo.length > 400) _undo.removeAt(0);
  }

  bool get canUndo => _undo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    final m = _undo.removeLast();
    marks[m.index] = m.before;
  }

  /// Remove every mark that contradicts the picture. Offered explicitly rather
  /// than done automatically — silently undoing someone's work is disorienting.
  int clearMistakes() {
    var n = 0;
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (!isEditable(i)) continue;
      final m = marks[i];
      if (m == kMarkNone) continue;
      final shouldFill = puzzle.solution[i];
      if ((m == kMarkFilled && !shouldFill) ||
          (m == kMarkEmpty && shouldFill)) {
        _push(i, kMarkNone);
        n++;
      }
    }
    return n;
  }

  bool get hasMistakes {
    for (var i = 0; i < puzzle.cellCount; i++) {
      final m = marks[i];
      if (m == kMarkNone) continue;
      final shouldFill = puzzle.solution[i];
      if ((m == kMarkFilled && !shouldFill) ||
          (m == kMarkEmpty && shouldFill)) {
        return true;
      }
    }
    return false;
  }

  bool isWrong(int i) {
    final m = marks[i];
    if (m == kMarkNone) return false;
    final shouldFill = puzzle.solution[i];
    return (m == kMarkFilled && !shouldFill) ||
        (m == kMarkEmpty && shouldFill);
  }

  /// Whether a row/column's clues are fully accounted for, so the board can
  /// grey those clues out. Standard newspaper practice and a big scanning aid.
  bool isRowComplete(int r) {
    for (var c = 0; c < puzzle.width; c++) {
      final i = r * puzzle.width + c;
      if (puzzle.solution[i] && marks[i] != kMarkFilled) return false;
      if (!puzzle.solution[i] && marks[i] == kMarkFilled) return false;
    }
    return true;
  }

  bool isColComplete(int c) {
    for (var r = 0; r < puzzle.height; r++) {
      final i = r * puzzle.width + c;
      if (puzzle.solution[i] && marks[i] != kMarkFilled) return false;
      if (!puzzle.solution[i] && marks[i] == kMarkFilled) return false;
    }
    return true;
  }

  // ------------------------------------------------------------------ hints

  /// The next deduction available, WITH the reasoning.
  ///
  /// Two kinds, tried in order:
  ///   1. If the player has made a mistake, the most useful help is pointing at
  ///      it — every later deduction built on it will be wrong.
  ///   2. Otherwise, find a line where logic alone forces a square, and say
  ///      which line and why. That is a technique the player can reuse; a hint
  ///      that just fills a square teaches nothing.
  Hint? nextHint() {
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (isWrong(i)) {
        final r = puzzle.rowOf(i) + 1;
        final c = puzzle.colOf(i) + 1;
        return Hint(
            i,
            puzzle.solution[i] ? kFilled : kEmpty,
            'Row $r, column $c is marked wrongly. Everything you work out from '
            'here will be wrong too, so it is worth fixing first.');
      }
    }

    // Feed what the player already knows into the line solver and see what it
    // can prove that they have not yet marked.
    final known = <int, int>{};
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (marks[i] == kMarkFilled) known[i] = kFilled;
      if (marks[i] == kMarkEmpty) known[i] = kEmpty;
    }

    final ls = LineSolver();

    // Rows first, then columns — matches how people read the board.
    for (var r = 0; r < puzzle.height; r++) {
      final line = List<int>.generate(
          puzzle.width, (c) => known[r * puzzle.width + c] ?? kUnknown);
      final before = List<int>.of(line);
      if (!ls.solve(line, puzzle.rowClues[r])) continue;
      for (var c = 0; c < puzzle.width; c++) {
        if (before[c] == kUnknown && line[c] != kUnknown) {
          final i = r * puzzle.width + c;
          if (!isEditable(i)) continue;
          return Hint(
              i,
              line[c],
              _explainLine(
                  isRow: true,
                  n: r + 1,
                  clues: puzzle.rowClues[r],
                  pos: c + 1,
                  fill: line[c] == kFilled,
                  length: puzzle.width));
        }
      }
    }

    for (var c = 0; c < puzzle.width; c++) {
      final line = List<int>.generate(
          puzzle.height, (r) => known[r * puzzle.width + c] ?? kUnknown);
      final before = List<int>.of(line);
      if (!ls.solve(line, puzzle.colClues[c])) continue;
      for (var r = 0; r < puzzle.height; r++) {
        if (before[r] == kUnknown && line[r] != kUnknown) {
          final i = r * puzzle.width + c;
          if (!isEditable(i)) continue;
          return Hint(
              i,
              line[r],
              _explainLine(
                  isRow: false,
                  n: c + 1,
                  clues: puzzle.colClues[c],
                  pos: r + 1,
                  fill: line[r] == kFilled,
                  length: puzzle.height));
        }
      }
    }

    // Nothing provable from a single line: fall back to the picture.
    for (var i = 0; i < puzzle.cellCount; i++) {
      if (!isEditable(i) && marks[i] != kMarkNone) continue;
      if (puzzle.solution[i] && marks[i] != kMarkFilled) {
        return Hint(i, kFilled,
            'Row ${puzzle.rowOf(i) + 1}, column ${puzzle.colOf(i) + 1} is part '
            'of the picture.');
      }
    }
    return null;
  }

  static String _explainLine({
    required bool isRow,
    required int n,
    required List<int> clues,
    required int pos,
    required bool fill,
    required int length,
  }) {
    final where = isRow ? 'Row $n' : 'Column $n';
    final other = isRow ? 'column $pos' : 'row $pos';
    final list = clues.join(', ');
    final total = clues.fold<int>(0, (a, b) => a + b);
    final gaps = clues.length - 1;
    final slack = length - total - gaps;

    if (fill) {
      // The classic overlap argument, stated plainly.
      if (clues.length == 1 && slack < clues[0] && slack >= 0) {
        return '$where needs a block of ${clues[0]} in $length squares. '
            'Slide it as far left as it goes, then as far right as it goes — '
            'the squares covered both times must be filled, and $other is one '
            'of them.';
      }
      return '$where is $list. Try the blocks pushed all the way to one end, '
            'then all the way to the other. Any square covered both times must '
            'be filled — $other is one of them.';
    }

    if (total == 0) {
      return '$where has a 0, so nothing in it is filled — including $other.';
    }
    return '$where is $list. Those blocks cannot reach $other whichever way '
        'they are arranged, so it can be crossed out.';
  }

  // ------------------------------------------------------------------- save

  Map<String, dynamic> toJson() => {
        'v': 1,
        'p': puzzle.toJson(),
        'm': marks,
        'sel': selected,
        'tool': tool.index,
        't': elapsedSeconds,
        'mis': mistakes,
        'h': hintsUsed,
      };

  String encode() => jsonEncode(toJson());

  /// Returns null on anything malformed. A corrupt save must cost the player
  /// their progress, never crash the app on launch.
  static GameState? fromJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final p = Puzzle.fromJson(j['p'] as Map<String, dynamic>);
      if (p == null) return null;
      final marks = (j['m'] as List).map((e) => e as int).toList();
      if (marks.length != p.cellCount) return null;
      for (final m in marks) {
        if (m != kMarkNone && m != kMarkEmpty && m != kMarkFilled) return null;
      }
      final g = GameState(p);
      g.marks = marks;
      g.selected = (j['sel'] as int?) ?? -1;
      final ti = (j['tool'] as int?) ?? 0;
      g.tool = (ti >= 0 && ti < Tool.values.length) ? Tool.values[ti] : Tool.fill;
      g.elapsedSeconds = (j['t'] as int?) ?? 0;
      g.mistakes = (j['mis'] as int?) ?? 0;
      g.hintsUsed = (j['h'] as int?) ?? 0;
      return g;
    } catch (_) {
      return null;
    }
  }
}
