/// Nonogram (picture-logic) engine.
///
/// PURE DART — no Flutter imports — so the whole thing unit-tests on a bare VM.
///
/// The two invariants this file exists to guarantee:
///
///   1. **Exactly one solution.** Verified by an exhaustive counter on every
///      emitted puzzle.
///   2. **No guessing is ever required.** Every puzzle we ship can be finished
///      by reasoning about one row or one column at a time — the technique a
///      human actually uses. A puzzle that is technically unique but needs a
///      trial-and-error branch is *rejected*, because for this audience
///      "I got stuck and had to guess" is indistinguishable from "the app is
///      broken".
///
/// Invariant 2 is strictly stronger than invariant 1 (line-solvable implies
/// unique), but both are asserted separately: if the line solver ever gains a
/// bug that makes it over-deduce, the independent solution counter catches it.
library;

/// Cell states used by the solver. Deliberately ints, not an enum, because the
/// line solver runs millions of times during generation.
const int kUnknown = -1;
const int kEmpty = 0;
const int kFilled = 1;

class Difficulty {
  final String label;
  final int size;

  /// Roughly what fraction of the grid is filled. Sparser grids give longer
  /// clue-free stretches, which are easier to reason about.
  final double density;

  const Difficulty._(this.label, this.size, this.density);

  static const gentle = Difficulty._('Gentle', 5, 0.52);
  static const easy = Difficulty._('Easy', 8, 0.50);
  static const medium = Difficulty._('Medium', 10, 0.50);
  static const hard = Difficulty._('Hard', 12, 0.48);

  /// Plain, encouraging names only. Never "expert" or "evil" — a name that
  /// tells someone they are about to fail stops them opening it.
  static const all = <Difficulty>[gentle, easy, medium, hard];

  static Difficulty byLabel(String l) =>
      all.firstWhere((d) => d.label == l, orElse: () => gentle);

  @override
  String toString() => label;
}

/// Thrown when generation cannot produce a puzzle meeting both invariants.
/// Callers show a friendly retry rather than crashing.
class GenerationFailure implements Exception {
  final String message;
  GenerationFailure(this.message);
  @override
  String toString() => 'GenerationFailure: $message';
}

/// An immutable puzzle: the clues, the picture, and any pre-revealed cells.
class Puzzle {
  final int width;
  final int height;

  /// Clue numbers per row, top to bottom. An empty line is `[0]`, never `[]`,
  /// so the UI always has something to draw.
  final List<List<int>> rowClues;

  /// Clue numbers per column, left to right.
  final List<List<int>> colClues;

  /// The answer picture: `true` = filled. Row-major, length width*height.
  final List<bool> solution;

  /// Cells revealed from the start. Kept as small as possible; they exist only
  /// to collapse ambiguity while preserving the picture (see [Generator]).
  final Set<int> givens;

  /// What the picture shows, e.g. "Cat". Shown only AFTER solving, as the
  /// payoff — showing it up front would give the puzzle away.
  final String pictureName;

  final Difficulty difficulty;

  const Puzzle({
    required this.width,
    required this.height,
    required this.rowClues,
    required this.colClues,
    required this.solution,
    required this.givens,
    required this.pictureName,
    required this.difficulty,
  });

  int get cellCount => width * height;
  int index(int r, int c) => r * width + c;
  int rowOf(int i) => i ~/ width;
  int colOf(int i) => i % width;

  /// How many cells must be filled in total — shown as a progress target.
  int get filledTarget => solution.where((b) => b).length;

  Map<String, dynamic> toJson() => {
        'w': width,
        'h': height,
        'rc': rowClues,
        'cc': colClues,
        'sol': solution.map((b) => b ? 1 : 0).toList(),
        'giv': givens.toList()..sort(),
        'name': pictureName,
        'diff': difficulty.label,
      };

  /// Returns null rather than throwing on malformed input: a corrupt save must
  /// cost the player their progress, not crash the app on launch.
  static Puzzle? fromJson(Map<String, dynamic> j) {
    try {
      final w = j['w'] as int;
      final h = j['h'] as int;
      final sol = (j['sol'] as List).map((e) => (e as int) == 1).toList();
      if (sol.length != w * h) return null;
      final rc = (j['rc'] as List)
          .map((e) => (e as List).map((x) => x as int).toList())
          .toList();
      final cc = (j['cc'] as List)
          .map((e) => (e as List).map((x) => x as int).toList())
          .toList();
      if (rc.length != h || cc.length != w) return null;
      return Puzzle(
        width: w,
        height: h,
        rowClues: rc,
        colClues: cc,
        solution: sol,
        givens: ((j['giv'] as List?) ?? const []).map((e) => e as int).toSet(),
        pictureName: (j['name'] as String?) ?? 'Picture',
        difficulty: Difficulty.byLabel((j['diff'] as String?) ?? 'Gentle'),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Derive the clue numbers for one line of the picture.
///
/// A line with nothing in it yields `[0]`, matching newspaper convention.
List<int> cluesForLine(List<bool> line) {
  final out = <int>[];
  var run = 0;
  for (final f in line) {
    if (f) {
      run++;
    } else if (run > 0) {
      out.add(run);
      run = 0;
    }
  }
  if (run > 0) out.add(run);
  if (out.isEmpty) out.add(0);
  return out;
}

/// Constraint propagation for a single line.
///
/// Given the current knowledge of a line and its clues, deduce every cell whose
/// value is the same in ALL valid arrangements. This is exactly the deduction a
/// human performs when they look at one row and say "that square must be
/// filled" — which is why the hint system can explain itself in plain words.
///
/// Returns `false` if the clues cannot be satisfied at all (a contradiction);
/// in that case [line] may have been partially modified and must be discarded.
class LineSolver {
  /// Reusable scratch buffers. Generation calls this hundreds of thousands of
  /// times, and allocating fresh lists each call dominated the profile.
  List<bool> _reach = [];
  List<bool> _finish = [];
  List<bool> _canFill = [];
  List<bool> _canEmpty = [];
  int _n = -1, _k = -1;

  void _ensure(int n, int k) {
    if (_n == n && _k == k) return;
    _n = n;
    _k = k;
    _reach = List<bool>.filled((n + 1) * (k + 1), false);
    _finish = List<bool>.filled((n + 1) * (k + 1), false);
    _canFill = List<bool>.filled(n, false);
    _canEmpty = List<bool>.filled(n, false);
  }

  /// True if clue block [ci] of length `len` can sit at [pos].
  static bool _fits(List<int> line, int pos, int len) {
    final n = line.length;
    if (pos + len > n) return false;
    for (var i = pos; i < pos + len; i++) {
      if (line[i] == kEmpty) return false;
    }
    // The cell straight after a block must not be filled, or the block would
    // be longer than the clue says.
    if (pos + len < n && line[pos + len] == kFilled) return false;
    return true;
  }

  /// Deduce as much as possible about [line] in place.
  /// Returns false on contradiction.
  bool solve(List<int> line, List<int> clues) {
    final n = line.length;
    // `[0]` means "this line is empty" — not "a block of length zero".
    final cl = (clues.length == 1 && clues[0] == 0) ? const <int>[] : clues;
    final k = cl.length;
    _ensure(n, k);

    final w = k + 1;
    _reach.fillRange(0, _reach.length, false);
    _finish.fillRange(0, _finish.length, false);
    _canFill.fillRange(0, n, false);
    _canEmpty.fillRange(0, n, false);

    // ---- forward: which (pos, clueIndex) states are reachable from the start
    _reach[0 * w + 0] = true;
    for (var pos = 0; pos <= n; pos++) {
      for (var ci = 0; ci <= k; ci++) {
        if (!_reach[pos * w + ci]) continue;
        if (pos == n) continue;
        // Leave this cell empty.
        if (line[pos] != kFilled) _reach[(pos + 1) * w + ci] = true;
        // Or start clue ci here.
        if (ci < k && _fits(line, pos, cl[ci])) {
          final next = pos + cl[ci] + (pos + cl[ci] < n ? 1 : 0);
          _reach[next * w + (ci + 1)] = true;
        }
      }
    }

    // ---- backward: from which states can we still consume every clue
    _finish[n * w + k] = true;
    for (var pos = n; pos >= 0; pos--) {
      for (var ci = k; ci >= 0; ci--) {
        if (pos == n) {
          // Only the "all clues used" state is a valid ending.
          continue;
        }
        var ok = false;
        if (line[pos] != kFilled && _finish[(pos + 1) * w + ci]) ok = true;
        if (!ok && ci < k && _fits(line, pos, cl[ci])) {
          final next = pos + cl[ci] + (pos + cl[ci] < n ? 1 : 0);
          if (_finish[next * w + (ci + 1)]) ok = true;
        }
        if (ok) _finish[pos * w + ci] = true;
      }
    }

    if (!(_reach[0] && _finish[0])) return false; // no arrangement at all

    // ---- mark: walk every live transition, recording what each cell can be
    for (var pos = 0; pos < n; pos++) {
      for (var ci = 0; ci <= k; ci++) {
        if (!_reach[pos * w + ci] || !_finish[pos * w + ci]) continue;
        if (line[pos] != kFilled && _finish[(pos + 1) * w + ci]) {
          _canEmpty[pos] = true;
        }
        if (ci < k && _fits(line, pos, cl[ci])) {
          final len = cl[ci];
          final next = pos + len + (pos + len < n ? 1 : 0);
          if (_finish[next * w + (ci + 1)]) {
            for (var i = pos; i < pos + len; i++) {
              _canFill[i] = true;
            }
            if (pos + len < n) _canEmpty[pos + len] = true;
          }
        }
      }
    }

    // ---- commit anything that is forced
    for (var i = 0; i < n; i++) {
      if (!_canFill[i] && !_canEmpty[i]) return false;
      if (_canFill[i] && !_canEmpty[i]) {
        if (line[i] == kEmpty) return false;
        line[i] = kFilled;
      } else if (_canEmpty[i] && !_canFill[i]) {
        if (line[i] == kFilled) return false;
        line[i] = kEmpty;
      }
    }
    return true;
  }
}

/// Result of trying to solve a grid by pure line logic.
enum SolveOutcome {
  /// Finished with no guessing — the only outcome we ship.
  solved,

  /// Consistent so far, but propagation ran out of deductions. A human would
  /// have to guess here.
  stalled,

  /// The clues contradict each other.
  contradiction,
}

class LineLogicResult {
  final SolveOutcome outcome;
  final List<int> grid;

  /// How many full row+column sweeps were needed. A decent proxy for how much
  /// work the puzzle is, used to grade difficulty.
  final int rounds;

  const LineLogicResult(this.outcome, this.grid, this.rounds);
}

/// The solver that decides whether a puzzle is fair.
class NonogramSolver {
  final int width;
  final int height;
  final List<List<int>> rowClues;
  final List<List<int>> colClues;
  final _ls = LineSolver();

  NonogramSolver({
    required this.width,
    required this.height,
    required this.rowClues,
    required this.colClues,
  });

  factory NonogramSolver.of(Puzzle p) => NonogramSolver(
        width: p.width,
        height: p.height,
        rowClues: p.rowClues,
        colClues: p.colClues,
      );

  /// Solve by line logic alone, never guessing.
  ///
  /// [start] optionally seeds known cells (the pre-revealed givens).
  LineLogicResult solveByLineLogic({Map<int, int>? start}) {
    final g = List<int>.filled(width * height, kUnknown);
    start?.forEach((i, v) => g[i] = v);

    final row = List<int>.filled(width, kUnknown);
    final col = List<int>.filled(height, kUnknown);
    var rounds = 0;

    while (true) {
      var changed = false;
      rounds++;

      for (var r = 0; r < height; r++) {
        final base = r * width;
        for (var c = 0; c < width; c++) {
          row[c] = g[base + c];
        }
        if (!_ls.solve(row, rowClues[r])) {
          return LineLogicResult(SolveOutcome.contradiction, g, rounds);
        }
        for (var c = 0; c < width; c++) {
          if (g[base + c] != row[c]) {
            g[base + c] = row[c];
            changed = true;
          }
        }
      }

      for (var c = 0; c < width; c++) {
        for (var r = 0; r < height; r++) {
          col[r] = g[r * width + c];
        }
        if (!_ls.solve(col, colClues[c])) {
          return LineLogicResult(SolveOutcome.contradiction, g, rounds);
        }
        for (var r = 0; r < height; r++) {
          if (g[r * width + c] != col[r]) {
            g[r * width + c] = col[r];
            changed = true;
          }
        }
      }

      if (!changed) break;
      // Safety valve. Each round must change at least one cell, so this can
      // never legitimately trigger; it exists so a solver bug degrades into a
      // rejected puzzle instead of an infinite loop that freezes the app.
      if (rounds > width * height + 4) break;
    }

    final done = !g.contains(kUnknown);
    return LineLogicResult(
        done ? SolveOutcome.solved : SolveOutcome.stalled, g, rounds);
  }

  /// Count solutions, stopping at [limit]. Independent of the line logic above
  /// so the two can cross-check each other.
  ///
  /// NOTE: [limit] is absolute and is passed down UNCHANGED. An earlier game in
  /// this portfolio shipped a bug where the remaining budget was passed into
  /// the recursion, which disabled the pruning guard and turned a bounded count
  /// into an exhaustive walk of the whole search space.
  int countSolutions({int limit = 2, Map<int, int>? start}) {
    final g = List<int>.filled(width * height, kUnknown);
    start?.forEach((i, v) => g[i] = v);
    var total = 0;
    _count(g, limit, () => total++, () => total);
    return total;
  }

  void _count(List<int> g, int limit, void Function() onSolution,
      int Function() totalNow) {
    if (totalNow() >= limit) return;

    final work = List<int>.of(g);
    final r = _propagate(work);
    if (r == SolveOutcome.contradiction) return;
    if (r == SolveOutcome.solved) {
      onSolution();
      return;
    }

    final pivot = work.indexOf(kUnknown);
    for (final guess in const [kFilled, kEmpty]) {
      if (totalNow() >= limit) return;
      final branch = List<int>.of(work);
      branch[pivot] = guess;
      _count(branch, limit, onSolution, totalNow);
    }
  }

  SolveOutcome _propagate(List<int> g) {
    final row = List<int>.filled(width, kUnknown);
    final col = List<int>.filled(height, kUnknown);
    while (true) {
      var changed = false;
      for (var r = 0; r < height; r++) {
        final base = r * width;
        for (var c = 0; c < width; c++) {
          row[c] = g[base + c];
        }
        if (!_ls.solve(row, rowClues[r])) return SolveOutcome.contradiction;
        for (var c = 0; c < width; c++) {
          if (g[base + c] != row[c]) {
            g[base + c] = row[c];
            changed = true;
          }
        }
      }
      for (var c = 0; c < width; c++) {
        for (var r = 0; r < height; r++) {
          col[r] = g[r * width + c];
        }
        if (!_ls.solve(col, colClues[c])) return SolveOutcome.contradiction;
        for (var r = 0; r < height; r++) {
          if (g[r * width + c] != col[r]) {
            g[r * width + c] = col[r];
            changed = true;
          }
        }
      }
      if (!changed) break;
    }
    return g.contains(kUnknown) ? SolveOutcome.stalled : SolveOutcome.solved;
  }
}

/// A single deduction the player could make right now, in plain words.
class Hint {
  final int index;

  /// What the cell should become: [kFilled] or [kEmpty].
  final int value;

  /// Plain-language explanation of WHY. A hint that just fills a square teaches
  /// nothing and leaves the player equally stuck next time.
  final String explanation;

  const Hint(this.index, this.value, this.explanation);
}
