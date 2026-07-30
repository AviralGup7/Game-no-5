/// Puzzle generation.
///
/// PURE DART — no Flutter imports.
///
/// The approach, and why:
///
/// A nonogram is fully determined by its picture — the clues are just a
/// summary of it. So unlike sudoku or kakuro there is nothing to "dig out";
/// the only questions are (a) is the picture's clue set uniquely solvable, and
/// (b) can a human get there without guessing.
///
/// Most hand-drawn pictures fail (b). Rather than throw those pictures away —
/// they are the entire appeal of the game — we REVEAL the fewest starting
/// cells that make the puzzle line-solvable. Crucially we only ever reveal a
/// cell at a point where the line solver is actually stuck, so no given is
/// wasted, and the picture is preserved exactly as drawn.
///
/// This mirrors the fix that rescued the kakuro generator in this portfolio:
/// when a puzzle is ambiguous, add the minimum information at the exact point
/// of ambiguity rather than regenerating and hoping.
library;

import 'nonogram_engine.dart';
import 'pictures.dart';

class Generator {
  /// Deterministic PRNG. Same seed anywhere in the world -> same puzzle, with
  /// no server involved. A 64-bit LCG; `Random` is not guaranteed stable
  /// across Dart releases, and the daily puzzle must be.
  int _state;

  Generator(int seed) : _state = (seed == 0 ? 0x2545F491 : seed) & 0x7FFFFFFF;

  int _next(int bound) {
    _state = (_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return _state % bound;
  }

  /// Build a puzzle of the requested difficulty.
  ///
  /// Throws [GenerationFailure] only if the picture library for that size is
  /// empty or every candidate is degenerate — which the tests assert cannot
  /// happen for the shipped library.
  Puzzle generate(Difficulty d) {
    final lib = pictureLibrary[d.size];
    if (lib == null || lib.isEmpty) {
      throw GenerationFailure('No pictures for size ${d.size}');
    }

    // Try pictures in a seed-shuffled order so a given date reliably picks the
    // same one, but different dates spread across the whole library.
    final order = List<int>.generate(lib.length, (i) => i);
    for (var i = order.length - 1; i > 0; i--) {
      final j = _next(i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }

    for (final idx in order) {
      final pic = lib[idx];
      final p = _fromPicture(pic, d);
      if (p != null) return p;
    }
    throw GenerationFailure('No solvable picture at size ${d.size}');
  }

  /// Turn one picture into a fair puzzle, or return null if it cannot be made
  /// fair within the given budget.
  Puzzle? _fromPicture(Picture pic, Difficulty d) {
    final n = pic.size;
    final sol = pic.cells;

    // Clues are a pure function of the picture.
    final rowClues = <List<int>>[];
    for (var r = 0; r < n; r++) {
      rowClues.add(cluesForLine(
          List<bool>.generate(n, (c) => sol[r * n + c])));
    }
    final colClues = <List<int>>[];
    for (var c = 0; c < n; c++) {
      colClues.add(cluesForLine(
          List<bool>.generate(n, (r) => sol[r * n + c])));
    }

    final solver = NonogramSolver(
        width: n, height: n, rowClues: rowClues, colClues: colClues);

    // Reveal cells until line logic alone finishes the grid.
    final givens = <int>{};
    final start = <int, int>{};
    // A cap well above what any shipped picture needs; if we ever hit it the
    // picture is pathological and gets skipped rather than shipping something
    // covered in freebies.
    final maxGivens = (n * n * 0.18).ceil();

    for (var attempt = 0; attempt <= maxGivens; attempt++) {
      final res = solver.solveByLineLogic(start: start);

      if (res.outcome == SolveOutcome.contradiction) {
        // Would mean cluesForLine and the solver disagree — a real bug, not a
        // property of the picture.
        return null;
      }

      if (res.outcome == SolveOutcome.solved) {
        // Cross-check with the independent counter. Belt and braces: if the
        // line solver ever over-deduces, this catches it before a player does.
        final count = solver.countSolutions(limit: 2, start: start);
        if (count != 1) return null;
        // And the thing it solved to must be the picture we drew.
        for (var i = 0; i < n * n; i++) {
          final want = sol[i] ? kFilled : kEmpty;
          if (res.grid[i] != want) return null;
        }
        return Puzzle(
          width: n,
          height: n,
          rowClues: rowClues,
          colClues: colClues,
          solution: sol,
          givens: givens,
          pictureName: pic.name,
          difficulty: d,
        );
      }

      // Stalled: reveal ONE cell, chosen at the point of ambiguity.
      final stuck = <int>[];
      for (var i = 0; i < n * n; i++) {
        if (res.grid[i] == kUnknown) stuck.add(i);
      }
      if (stuck.isEmpty) return null; // impossible, but never loop forever
      final pick = stuck[_next(stuck.length)];
      givens.add(pick);
      start[pick] = sol[pick] ? kFilled : kEmpty;
    }

    return null; // needed too much help
  }
}

/// Difficulty grading, reported for tests and the puzzle info sheet.
///
/// "Hard" here means *more work*, never *needs a guess* — every shipped puzzle
/// is line-solvable by construction.
class PuzzleStats {
  final int rounds;
  final int givens;
  final int filled;
  const PuzzleStats(this.rounds, this.givens, this.filled);
}

PuzzleStats analyse(Puzzle p) {
  final solver = NonogramSolver.of(p);
  final start = <int, int>{
    for (final i in p.givens) i: p.solution[i] ? kFilled : kEmpty
  };
  final r = solver.solveByLineLogic(start: start);
  return PuzzleStats(r.rounds, p.givens.length, p.filledTarget);
}
