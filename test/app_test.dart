/// Widget + state tests. These assert the ACCESSIBILITY and CORRECTNESS
/// guarantees, not just that widgets render.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:large_print_nonogram/engine/nonogram_engine.dart';
import 'package:large_print_nonogram/engine/generator.dart';
import 'package:large_print_nonogram/models/game_state.dart';
import 'package:large_print_nonogram/services/settings.dart';
import 'package:large_print_nonogram/services/progress.dart';
import 'package:large_print_nonogram/services/daily_puzzle.dart';
import 'package:large_print_nonogram/services/ads.dart';
import 'package:large_print_nonogram/services/audio.dart';
import 'package:large_print_nonogram/widgets/app_theme.dart';
import 'package:large_print_nonogram/widgets/nonogram_board.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Settings defaults', () {
    test('opens large with helpers on', () async {
      final s = Settings();
      await s.load();
      // The app OPENS large. Shipping at 1.0 and expecting people to find a
      // settings screen is the mistake every competitor makes.
      expect(s.fontScale, 1.15);
      expect(s.showMistakes, isTrue);
      expect(s.highlightLine, isTrue);
      expect(s.autoCross, isTrue);
      expect(s.seenTutorial, isFalse);
    });

    test('font scale clamps to a legible range', () async {
      final s = Settings();
      await s.load();
      await s.setFontScale(5.0);
      expect(s.fontScale, 1.6);
      await s.setFontScale(0.1);
      expect(s.fontScale, 0.85);
    });

    test('preferences survive a reload', () async {
      final s = Settings();
      await s.load();
      await s.setDarkMode(true);
      await s.setAutoCross(false);
      await s.setFontScale(1.4);
      final again = Settings();
      await again.load();
      expect(again.darkMode, isTrue);
      expect(again.autoCross, isFalse);
      expect(again.fontScale, 1.4);
    });
  });

  group('Audio', () {
    test('music is opt-in, sound effects are on', () async {
      final s = Settings();
      await s.load();
      // Unprompted music is an uninstall trigger for this audience.
      expect(s.music, isFalse);
      expect(s.sound, isTrue);
    });

    test('audio preferences persist', () async {
      final s = Settings();
      await s.load();
      await s.setMusic(true);
      await s.setSound(false);
      final again = Settings();
      await again.load();
      expect(again.music, isTrue);
      expect(again.sound, isFalse);
    });

    test('the silent fallback never throws without a platform', () {
      final a = AudioService.silent();
      expect(a.isReady, isFalse);
      for (final s in Sfx.values) {
        a.play(s);
      }
      expect(() => a.dispose(), returnsNormally);
    });

    test('AudioService.instance is never null', () {
      expect(AudioService.instance, isNotNull);
    });
  });

  group('Progress + streaks', () {
    test('counts consecutive days and persists', () async {
      final p = Progress();
      await p.load();
      final today = DateTime.now();
      await p.markComplete(today,
          seconds: 100, difficultyKey: 'Easy', pictureName: 'Cat');
      await p.markComplete(today.subtract(const Duration(days: 1)),
          seconds: 90, difficultyKey: 'Easy', pictureName: 'Duck');
      expect(p.currentStreak, 2);

      final again = Progress();
      await again.load();
      expect(again.currentStreak, 2);
      expect(again.totalPuzzles, 2);
    });

    test('a gap breaks the streak', () async {
      final p = Progress();
      await p.load();
      final today = DateTime.now();
      await p.markComplete(today,
          seconds: 10, difficultyKey: 'Easy', pictureName: 'Cat');
      await p.markComplete(today.subtract(const Duration(days: 3)),
          seconds: 10, difficultyKey: 'Easy', pictureName: 'Owl');
      expect(p.currentStreak, 1);
      expect(p.bestStreak, 1);
    });

    test('best times only improve', () async {
      final p = Progress();
      await p.load();
      await p.recordPractice(300, 'Medium', 'Ship');
      await p.recordPractice(500, 'Medium', 'Owl');
      expect(p.bestTimes['Medium'], 300);
      await p.recordPractice(200, 'Medium', 'Bird');
      expect(p.bestTimes['Medium'], 200);
    });

    test('the album collects every picture solved', () async {
      final p = Progress();
      await p.load();
      await p.recordPractice(10, 'Easy', 'Cat');
      await p.recordPractice(10, 'Easy', 'Duck');
      await p.recordPractice(10, 'Easy', 'Cat');
      // A set: solving the same picture twice is not a new discovery.
      expect(p.album, {'Cat', 'Duck'});
    });
  });

  group('GameState', () {
    Puzzle puzzle() => Generator(4242).generate(Difficulty.gentle);

    test('revealed cells are pre-marked and not editable', () {
      final p = Generator(7).generate(Difficulty.easy);
      final g = GameState(p);
      for (final i in p.givens) {
        expect(g.isEditable(i), isFalse);
        expect(g.marks[i], p.solution[i] ? kMarkFilled : kMarkEmpty);
      }
    });

    test('filling a square that should be empty is a mistake', () {
      final p = puzzle();
      final g = GameState(p);
      final wrongCell = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => !p.solution[i] && g.isEditable(i));
      g.tool = Tool.fill;
      expect(g.apply(wrongCell), isTrue);
      expect(g.mistakes, 1);
      expect(g.isWrong(wrongCell), isTrue);
    });

    test('crossing out a square that should be filled is a mistake', () {
      final p = puzzle();
      final g = GameState(p);
      final fillCell = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => p.solution[i] && g.isEditable(i));
      g.tool = Tool.cross;
      expect(g.apply(fillCell), isTrue);
      expect(g.mistakes, 1);
    });

    test('tapping the same square twice clears it', () {
      final p = puzzle();
      final g = GameState(p);
      final i = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => p.solution[i] && g.isEditable(i));
      g.tool = Tool.fill;
      g.apply(i);
      expect(g.marks[i], kMarkFilled);
      g.apply(i);
      expect(g.marks[i], kMarkNone);
    });

    test('undo restores the previous mark', () {
      final p = puzzle();
      final g = GameState(p);
      final i = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => g.isEditable(i));
      g.tool = Tool.fill;
      g.apply(i);
      expect(g.canUndo, isTrue);
      g.undo();
      expect(g.marks[i], kMarkNone);
    });

    test('filling the picture solves the puzzle', () {
      final p = puzzle();
      final g = GameState(p);
      g.tool = Tool.fill;
      for (var i = 0; i < p.cellCount; i++) {
        if (p.solution[i] && g.isEditable(i)) g.apply(i);
      }
      expect(g.isSolved, isTrue);
      expect(g.mistakes, 0);
    });

    test('leaving squares uncrossed still counts as solved', () {
      // Demanding bookkeeping the player did not need is the kind of pedantry
      // that gets an app uninstalled.
      final p = puzzle();
      final g = GameState(p);
      g.tool = Tool.fill;
      for (var i = 0; i < p.cellCount; i++) {
        if (p.solution[i] && g.isEditable(i)) g.apply(i);
      }
      final anyBlank = g.marks.any((m) => m == kMarkNone);
      expect(anyBlank, isTrue, reason: 'test needs an unmarked empty square');
      expect(g.isSolved, isTrue);
    });

    test('clearing mistakes removes only the wrong marks', () {
      final p = puzzle();
      final g = GameState(p);
      g.tool = Tool.fill;
      final right = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => p.solution[i] && g.isEditable(i));
      final wrong = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => !p.solution[i] && g.isEditable(i));
      g.apply(right);
      g.apply(wrong);
      expect(g.hasMistakes, isTrue);
      final n = g.clearMistakes();
      expect(n, 1);
      expect(g.marks[right], kMarkFilled);
      expect(g.marks[wrong], kMarkNone);
      expect(g.hasMistakes, isFalse);
    });

    test('a completed line is reported complete', () {
      final p = puzzle();
      final g = GameState(p);
      g.tool = Tool.fill;
      for (var c = 0; c < p.width; c++) {
        final i = c; // row 0
        if (p.solution[i] && g.isEditable(i)) g.apply(i);
      }
      expect(g.isRowComplete(0), isTrue);
    });

    test('save and restore round-trips exactly', () {
      final p = puzzle();
      final g = GameState(p);
      g.tool = Tool.cross;
      final i = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => !p.solution[i] && g.isEditable(i));
      g.apply(i);
      g.elapsedSeconds = 321;
      g.hintsUsed = 2;

      final back = GameState.fromJson(g.encode());
      expect(back, isNotNull);
      expect(back!.marks, g.marks);
      expect(back.elapsedSeconds, 321);
      expect(back.hintsUsed, 2);
      expect(back.tool, Tool.cross);
      expect(back.puzzle.pictureName, p.pictureName);
    });

    test('a corrupt save returns null instead of throwing', () {
      expect(GameState.fromJson('not json at all'), isNull);
      expect(GameState.fromJson('{"v":1}'), isNull);
      expect(GameState.fromJson('{"v":1,"p":{"w":3,"h":3},"m":[0]}'), isNull);
    });
  });

  group('Hints', () {
    test('a hint is always correct and explains itself', () {
      final p = Generator(88).generate(Difficulty.gentle);
      final g = GameState(p);
      final h = g.nextHint();
      expect(h, isNotNull);
      final shouldFill = p.solution[h!.index];
      expect(h.value, shouldFill ? kFilled : kEmpty);
      // A hint that just fills a square teaches nothing.
      expect(h.explanation.length, greaterThan(25));
      expect(h.explanation, matches(RegExp(r'[Rr]ow|[Cc]olumn')));
    });

    test('a mistake is pointed out before anything else', () {
      final p = Generator(88).generate(Difficulty.gentle);
      final g = GameState(p);
      g.tool = Tool.fill;
      final wrong = List.generate(p.cellCount, (i) => i)
          .firstWhere((i) => !p.solution[i] && g.isEditable(i));
      g.apply(wrong);
      final h = g.nextHint();
      expect(h, isNotNull);
      expect(h!.index, wrong);
      expect(h.explanation.toLowerCase(), contains('wrong'));
    });

    test('hints can finish a whole puzzle', () {
      final p = Generator(1234).generate(Difficulty.gentle);
      final g = GameState(p);
      var guard = 0;
      while (!g.isSolved && guard++ < 500) {
        final h = g.nextHint();
        if (h == null) break;
        g.setMark(h.index, h.value == kFilled ? kMarkFilled : kMarkEmpty);
      }
      expect(g.isSolved, isTrue);
      expect(g.mistakes, 0);
    });

    test('returns null on a finished grid', () {
      final p = Generator(1234).generate(Difficulty.gentle);
      final g = GameState(p);
      for (var i = 0; i < p.cellCount; i++) {
        g.setMark(i, p.solution[i] ? kMarkFilled : kMarkEmpty);
      }
      expect(g.nextHint(), isNull);
    });
  });

  group('Regressions', () {
    test('auto-cross must NOT trigger on a wrong-but-right-sized line', () {
      // The bug: auto-cross compared only the COUNT of filled cells against
      // the clue total. Fill the right NUMBER of squares in the wrong PLACES
      // and the app confidently crossed out squares that needed filling -
      // the app telling the player something false.
      final p = Generator(4242).generate(Difficulty.gentle);
      final g = GameState(p);

      // Find a row with at least one filled and one empty editable cell.
      int? target;
      for (var r = 0; r < p.height; r++) {
        var filled = 0, empty = 0;
        for (var c = 0; c < p.width; c++) {
          final i = r * p.width + c;
          if (!g.isEditable(i)) continue;
          p.solution[i] ? filled++ : empty++;
        }
        if (filled >= 1 && empty >= 1) {
          target = r;
          break;
        }
      }
      expect(target, isNotNull, reason: 'need a mixed row for this test');

      // Deliberately fill the WRONG cells, keeping the count correct.
      final wrong = <int>[];
      final right = <int>[];
      for (var c = 0; c < p.width; c++) {
        final i = target! * p.width + c;
        if (!g.isEditable(i)) continue;
        (p.solution[i] ? right : wrong).add(i);
      }
      final n = right.length < wrong.length ? right.length : wrong.length;
      g.tool = Tool.fill;
      for (var k = 0; k < n; k++) {
        g.setMark(wrong[k], kMarkFilled);
      }

      // A row that is filled wrongly must never be treated as satisfied.
      expect(g.isRowComplete(target!), isFalse,
          reason: 'a wrongly-filled row was reported complete');
    });

    test('isRowComplete only accepts the CORRECT squares', () {
      final p = Generator(99).generate(Difficulty.gentle);
      final g = GameState(p);
      for (var r = 0; r < p.height; r++) {
        var any = false;
        for (var c = 0; c < p.width; c++) {
          final i = r * p.width + c;
          if (p.solution[i] && g.isEditable(i)) {
            g.setMark(i, kMarkFilled);
            any = true;
          }
        }
        if (any) {
          expect(g.isRowComplete(r), isTrue);
        }
      }
    });

    test('grouped cells undo as ONE action', () {
      // Auto-cross can mark a dozen squares from one tap. Undoing that must
      // take one press, not thirteen.
      final p = Generator(555).generate(Difficulty.gentle);
      final g = GameState(p);
      final editable = List.generate(p.cellCount, (i) => i)
          .where(g.isEditable)
          .toList();
      expect(editable.length, greaterThan(4));

      g.setMark(editable[0], kMarkFilled);
      final before = List<int>.of(g.marks);

      // One player action, then three cells attached to it.
      g.setMark(editable[1], kMarkEmpty);
      final grouped = <int>[editable[2], editable[3]];
      for (final i in grouped) {
        g.setMark(i, kMarkEmpty);
      }
      g.groupWithPrevious(grouped);

      g.undo();
      expect(g.marks, before,
          reason: 'one undo press did not clear the whole grouped action');
    });

    test('a paid-up player is never shown a rewarded ad', () async {
      final s = Settings();
      await s.load();
      await s.setAdFree(true);
      final ads = AdService(s);
      expect(await ads.showRewarded(), isTrue);
    });
  });

  group('Daily puzzle', () {
    test('is deterministic regardless of time of day', () {
      final a = DailyPuzzle.forDate(DateTime(2026, 7, 30, 6, 15));
      final b = DailyPuzzle.forDate(DateTime(2026, 7, 30, 23, 59));
      expect(a.pictureName, b.pictureName);
      expect(a.solution, b.solution);
    });

    test('consecutive days differ', () {
      final a = DailyPuzzle.forDate(DateTime(2026, 7, 30));
      final b = DailyPuzzle.forDate(DateTime(2026, 7, 31));
      expect(a.solution == b.solution && a.pictureName == b.pictureName,
          isFalse);
    });

    test('weekday ramp follows newspaper convention', () {
      // Monday gentle, Saturday hardest, Sunday eases off.
      expect(DailyPuzzle.difficultyForDate(DateTime(2026, 7, 27)).label,
          'Gentle');
      expect(DailyPuzzle.difficultyForDate(DateTime(2026, 8, 1)).label, 'Hard');
      expect(DailyPuzzle.difficultyForDate(DateTime(2026, 8, 2)).label, 'Easy');
    });

    test('a month of dailies all generate and stay unique', () {
      for (var day = 1; day <= 31; day++) {
        final p = DailyPuzzle.forDate(DateTime(2026, 3, day));
        final n = NonogramSolver.of(p).countSolutions(
            limit: 2,
            start: {
              for (final i in p.givens) i: p.solution[i] ? kFilled : kEmpty
            });
        expect(n, 1, reason: 'March $day has $n solutions');
      }
    });
  });

  group('Theme accessibility', () {
    test('buttons meet a 56dp minimum target', () {
      final t = AppTheme.light();
      final size =
          t.filledButtonTheme.style?.minimumSize?.resolve({}) ?? Size.zero;
      expect(size.height, greaterThanOrEqualTo(56));
    });

    test('high contrast is pure black on white', () {
      final t = AppTheme.light(highContrast: true);
      expect(t.colorScheme.surface, Colors.white);
      expect(t.colorScheme.onSurface, const Color(0xFF000000));
    });

    test('the crossed-out mark differs in hue from the filled mark', () {
      // Not just in lightness: the two states must survive colour-blindness.
      final s = AppTheme.light().colorScheme;
      final fill = HSLColor.fromColor(AppTheme.paintedCell(s));
      final cross = HSLColor.fromColor(AppTheme.crossColour(s));
      expect((fill.hue - cross.hue).abs(), greaterThan(40));
    });
  });

  group('Board widget', () {
    testWidgets('renders and reports the tapped cell', (tester) async {
      final p = Generator(5).generate(Difficulty.gentle);
      final g = GameState(p);
      int? tapped;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              height: 380,
              child: NonogramBoard(game: g, onCell: (i) => tapped = i),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NonogramBoard), findsOneWidget);
      // Tap near the bottom-right of the board: must land inside the grid,
      // not on a clue strip.
      final box = tester.getRect(find.byType(NonogramBoard));
      await tester.tapAt(Offset(box.right - 20, box.bottom - 20));
      await tester.pump();
      expect(tapped, isNotNull);
      expect(tapped, inInclusiveRange(0, p.cellCount - 1));
    });

    testWidgets('a tap on the clue strip is ignored', (tester) async {
      final p = Generator(5).generate(Difficulty.gentle);
      final g = GameState(p);
      int? tapped;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              height: 380,
              child: NonogramBoard(game: g, onCell: (i) => tapped = i),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(NonogramBoard));
      // Top-left corner is the junction of both clue strips - never a cell.
      await tester.tapAt(Offset(box.left + 2, box.top + 2));
      await tester.pump();
      expect(tapped, isNull);
    });
  });
}
