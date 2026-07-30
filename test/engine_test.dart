/// Engine tests. Pure Dart — these run on a bare VM with no Flutter binding.
///
/// The first group is the one that matters: it asserts the two invariants the
/// whole product rests on. If either ever fails, the app is shipping puzzles
/// that are unfair or unsolvable, which is worse than shipping nothing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:large_print_nonogram/engine/nonogram_engine.dart';
import 'package:large_print_nonogram/engine/generator.dart';
import 'package:large_print_nonogram/engine/pictures.dart';

Map<int, int> _startFor(Puzzle p) =>
    {for (final i in p.givens) i: p.solution[i] ? kFilled : kEmpty};

void main() {
  group('the two critical invariants', () {
    test('every generated puzzle has EXACTLY one solution', () {
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 12; seed++) {
          final p = Generator(seed * 7919).generate(d);
          final n = NonogramSolver.of(p)
              .countSolutions(limit: 2, start: _startFor(p));
          expect(n, 1,
              reason: '${d.label} seed $seed ("${p.pictureName}") '
                  'has $n solutions');
        }
      }
    });

    test('every generated puzzle is solvable WITHOUT guessing', () {
      // Strictly stronger than uniqueness, and the one players feel. A puzzle
      // that needs a trial-and-error branch is indistinguishable, to the
      // person holding the phone, from a broken app.
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 12; seed++) {
          final p = Generator(seed * 104729).generate(d);
          final r = NonogramSolver.of(p)
              .solveByLineLogic(start: _startFor(p));
          expect(r.outcome, SolveOutcome.solved,
              reason: '${d.label} seed $seed ("${p.pictureName}") stalls');
        }
      }
    });

    test('line logic reproduces the picture that was drawn', () {
      for (final d in Difficulty.all) {
        final p = Generator(31337).generate(d);
        final r =
            NonogramSolver.of(p).solveByLineLogic(start: _startFor(p));
        for (var i = 0; i < p.cellCount; i++) {
          expect(r.grid[i], p.solution[i] ? kFilled : kEmpty,
              reason: 'cell $i of ${p.pictureName}');
        }
      }
    });
  });

  group('clue derivation', () {
    test('runs are counted correctly', () {
      expect(cluesForLine([true, true, false, true]), [2, 1]);
      expect(cluesForLine([false, false, false]), [0]);
      expect(cluesForLine([true, true, true]), [3]);
      expect(cluesForLine([true, false, true, false, true]), [1, 1, 1]);
    });

    test('an empty line is [0], never an empty list', () {
      // The UI always needs something to draw in the clue strip.
      final c = cluesForLine([false, false]);
      expect(c, isNotEmpty);
      expect(c, [0]);
    });

    test('clues always match the puzzle solution', () {
      for (final d in Difficulty.all) {
        final p = Generator(555).generate(d);
        for (var r = 0; r < p.height; r++) {
          final line =
              List<bool>.generate(p.width, (c) => p.solution[r * p.width + c]);
          expect(p.rowClues[r], cluesForLine(line), reason: 'row $r');
        }
        for (var c = 0; c < p.width; c++) {
          final line = List<bool>.generate(
              p.height, (r) => p.solution[r * p.width + c]);
          expect(p.colClues[c], cluesForLine(line), reason: 'column $c');
        }
      }
    });
  });

  group('line solver', () {
    test('the overlap rule: 4 in 5 squares forces the middle three', () {
      final line = List<int>.filled(5, kUnknown);
      expect(LineSolver().solve(line, [4]), isTrue);
      expect(line, [kUnknown, kFilled, kFilled, kFilled, kUnknown]);
    });

    test('a full line is fully determined', () {
      final line = List<int>.filled(5, kUnknown);
      expect(LineSolver().solve(line, [5]), isTrue);
      expect(line.every((c) => c == kFilled), isTrue);
    });

    test('a zero clue empties the line', () {
      final line = List<int>.filled(4, kUnknown);
      expect(LineSolver().solve(line, [0]), isTrue);
      expect(line.every((c) => c == kEmpty), isTrue);
    });

    test('too little room is reported as a contradiction, not a crash', () {
      final line = List<int>.filled(3, kUnknown);
      expect(LineSolver().solve(line, [2, 2]), isFalse);
    });

    test('an existing mark that contradicts the clues is rejected', () {
      final line = [kEmpty, kUnknown, kUnknown];
      expect(LineSolver().solve(line, [3]), isFalse);
    });

    test('deduces from partial knowledge', () {
      // 1 1 in 3 squares has only one arrangement.
      final line = List<int>.filled(3, kUnknown);
      expect(LineSolver().solve(line, [1, 1]), isTrue);
      expect(line, [kFilled, kEmpty, kFilled]);
    });
  });

  group('picture library', () {
    test('every picture is square and non-degenerate', () {
      pictureLibrary.forEach((size, lib) {
        for (final pic in lib) {
          expect(pic.cells.length, size * size, reason: pic.name);
          final filled = pic.cells.where((b) => b).length;
          expect(filled, greaterThan(0), reason: '${pic.name} is blank');
          expect(filled, lessThan(size * size),
              reason: '${pic.name} is entirely filled');
        }
      });
    });

    test('no two pictures of a size are the same artwork', () {
      // A duplicate is invisible in review but shows up to a player as the
      // same puzzle twice. The first draft of 'Kite' was pixel-identical to
      // 'Diamond'; this test is why that was caught.
      pictureLibrary.forEach((size, lib) {
        final seen = <String, String>{};
        for (final pic in lib) {
          final key = pic.cells.map((b) => b ? '1' : '0').join();
          expect(seen.containsKey(key), isFalse,
              reason: '${pic.name} duplicates ${seen[key]}');
          seen[key] = pic.name;
        }
      });
    });

    test('the library is big enough for months of dailies', () {
      expect(pictureCount, greaterThanOrEqualTo(80));
      for (final d in Difficulty.all) {
        expect(pictureLibrary[d.size], isNotNull, reason: d.label);
        expect(pictureLibrary[d.size]!.length, greaterThanOrEqualTo(8),
            reason: '${d.label} has too few pictures');
      }
    });

    test('every picture in the library can be made into a fair puzzle', () {
      pictureLibrary.forEach((size, lib) {
        for (final pic in lib) {
          final n = pic.size;
          final sol = pic.cells;
          final rc = [
            for (var r = 0; r < n; r++)
              cluesForLine([for (var c = 0; c < n; c++) sol[r * n + c]])
          ];
          final cc = [
            for (var c = 0; c < n; c++)
              cluesForLine([for (var r = 0; r < n; r++) sol[r * n + c]])
          ];
          final s = NonogramSolver(
              width: n, height: n, rowClues: rc, colClues: cc);
          // With no help it may stall - that is expected and is what the
          // revealed cells are for - but it must never be contradictory.
          final r = s.solveByLineLogic();
          expect(r.outcome, isNot(SolveOutcome.contradiction),
              reason: '${pic.name} produces impossible clues');
        }
      });
    });
  });

  group('determinism', () {
    test('the same seed gives the same puzzle', () {
      for (final d in Difficulty.all) {
        final a = Generator(9001).generate(d);
        final b = Generator(9001).generate(d);
        expect(a.pictureName, b.pictureName);
        expect(a.solution, b.solution);
        expect(a.givens.toList()..sort(), b.givens.toList()..sort());
      }
    });

    test('different seeds spread across the library', () {
      final names = <String>{};
      for (var seed = 1; seed <= 40; seed++) {
        names.add(Generator(seed * 7919).generate(Difficulty.easy).pictureName);
      }
      expect(names.length, greaterThan(5),
          reason: 'generation is clustering on a few pictures');
    });
  });

  group('generation cost', () {
    test('stays fast enough to run on the UI thread', () {
      final sw = Stopwatch()..start();
      for (var seed = 1; seed <= 20; seed++) {
        Generator(seed * 7919).generate(Difficulty.hard);
      }
      sw.stop();
      final per = sw.elapsedMilliseconds / 20;
      // Measured at ~2 ms on the build machine. 60 ms leaves a wide margin for
      // a slow phone while still catching a real regression.
      expect(per, lessThan(60),
          reason: '${per}ms per puzzle would drop frames');
    });

    test('needs very few revealed cells', () {
      var total = 0, n = 0;
      for (final d in Difficulty.all) {
        for (var seed = 1; seed <= 15; seed++) {
          total += Generator(seed * 6151).generate(d).givens.length;
          n++;
        }
      }
      final avg = total / n;
      // Revealed cells are a necessary evil: each one is a square the player
      // did not get to work out. Keep the average under one.
      expect(avg, lessThan(1.0), reason: 'average $avg givens is too generous');
    });
  });

  group('difficulty', () {
    test('names are plain and encouraging', () {
      final labels = Difficulty.all.map((d) => d.label).toList();
      expect(labels, ['Gentle', 'Easy', 'Medium', 'Hard']);
      for (final l in labels) {
        expect(l.toLowerCase(), isNot(anyOf('expert', 'evil', 'insane')));
      }
    });

    test('grid size increases with difficulty', () {
      for (var i = 1; i < Difficulty.all.length; i++) {
        expect(Difficulty.all[i].size,
            greaterThan(Difficulty.all[i - 1].size));
      }
    });
  });

  group('serialisation', () {
    test('a puzzle round-trips exactly', () {
      final p = Generator(2024).generate(Difficulty.medium);
      final back = Puzzle.fromJson(p.toJson());
      expect(back, isNotNull);
      expect(back!.solution, p.solution);
      expect(back.rowClues, p.rowClues);
      expect(back.colClues, p.colClues);
      expect(back.pictureName, p.pictureName);
      expect(back.difficulty.label, p.difficulty.label);
      expect(back.givens, p.givens);
    });

    test('malformed data returns null instead of throwing', () {
      expect(Puzzle.fromJson({'nonsense': true}), isNull);
      expect(Puzzle.fromJson({'w': 5, 'h': 5, 'sol': [1, 0]}), isNull);
    });
  });
}
