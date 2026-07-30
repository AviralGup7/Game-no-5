library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../engine/nonogram_engine.dart';
import '../models/game_state.dart';
import '../services/settings.dart';
import '../services/progress.dart';
import '../services/ads.dart';
import '../services/audio.dart';
import '../widgets/nonogram_board.dart';
import '../widgets/app_theme.dart';

class GameScreen extends StatefulWidget {
  final GameState game;
  final Settings settings;
  final Progress progress;
  final AdService ads;
  final DateTime? dailyDate;
  final String title;

  const GameScreen({
    super.key,
    required this.game,
    required this.settings,
    required this.progress,
    required this.ads,
    required this.title,
    this.dailyDate,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Timer? _timer;
  int? _hintIndex;
  bool _finished = false;
  late final AnimationController _shake;
  late final Music _track;

  GameState get g => widget.game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260));
    _track = widget.dailyDate != null ? Music.gameplayA : Music.gameplayB;
    AudioService.instance.playMusic(_track);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // Elapsed only, never a countdown. Time pressure is the most common
    // complaint from older players, and a nonogram is a thinking game.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished) return;
      setState(() => g.elapsedSeconds++);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _startTimer();
      AudioService.instance.resumeFromBackground();
    } else {
      _timer?.cancel();
      AudioService.instance.pauseForBackground();
      _save();
    }
  }

  Future<void> _save() async {
    if (_finished) return;
    await widget.progress.saveGame(g.encode());
  }

  @override
  void dispose() {
    _timer?.cancel();
    AudioService.instance.stopMusic();
    _shake.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _haptic(bool ok) {
    if (!widget.settings.haptics) return;
    ok ? HapticFeedback.selectionClick() : HapticFeedback.mediumImpact();
  }

  /// Cross out the rest of a line once its clues are satisfied. This is the
  /// tedious bookkeeping half of a nonogram, and doing it by hand on a 12x12
  /// is where people give up.
  void _autoCross() {
    if (!widget.settings.autoCross) return;
    final p = g.puzzle;
    for (var r = 0; r < p.height; r++) {
      var filled = 0;
      for (var c = 0; c < p.width; c++) {
        if (g.marks[r * p.width + c] == kMarkFilled) filled++;
      }
      final need = p.rowClues[r].fold<int>(0, (a, b) => a + b);
      if (filled != need) continue;
      for (var c = 0; c < p.width; c++) {
        final i = r * p.width + c;
        if (g.marks[i] == kMarkNone) g.setMark(i, kMarkEmpty);
      }
    }
    for (var c = 0; c < p.width; c++) {
      var filled = 0;
      for (var r = 0; r < p.height; r++) {
        if (g.marks[r * p.width + c] == kMarkFilled) filled++;
      }
      final need = p.colClues[c].fold<int>(0, (a, b) => a + b);
      if (filled != need) continue;
      for (var r = 0; r < p.height; r++) {
        final i = r * p.width + c;
        if (g.marks[i] == kMarkNone) g.setMark(i, kMarkEmpty);
      }
    }
  }

  void _tapCell(int i) {
    if (!g.isEditable(i)) {
      setState(() => g.selected = i);
      _toast('That square was given to you');
      return;
    }
    setState(() {
      g.selected = i;
      _hintIndex = null;
      final wrong = g.apply(i);
      _haptic(!wrong);
      AudioService.instance.play(wrong ? Sfx.placeWrong : Sfx.placeGood);
      if (wrong) {
        _shake.forward(from: 0);
      } else {
        _autoCross();
      }
    });
    if (g.isSolved) _win();
    _save();
  }

  /// Drag-painting: apply the mark the stroke started with, without toggling.
  void _paint(int i, int mark) {
    if (!g.isEditable(i)) return;
    if (g.marks[i] == mark) return;
    setState(() {
      final wrong = g.setMark(i, mark);
      if (wrong) {
        _haptic(false);
        _shake.forward(from: 0);
      } else {
        _autoCross();
      }
      _hintIndex = null;
    });
    if (g.isSolved) _win();
    _save();
  }

  void _undo() {
    if (!g.canUndo) return;
    setState(g.undo);
    _haptic(true);
    AudioService.instance.play(Sfx.buttonTap);
    _save();
  }

  Future<void> _clearMistakes() async {
    if (!g.hasMistakes) {
      _toast('No mistakes to clear');
      return;
    }
    final n = g.clearMistakes();
    setState(() {});
    _toast(n == 1 ? 'Cleared 1 wrong square' : 'Cleared $n wrong squares');
    _save();
  }

  Future<void> _hint() async {
    final h = g.nextHint();
    if (h == null) {
      _toast('Nothing left to work out');
      return;
    }
    final granted = await widget.ads.showRewarded(context);
    if (!granted || !mounted) return;
    setState(() {
      g.setMark(h.index, h.value == kFilled ? kMarkFilled : kMarkEmpty);
      // A hint is help, not a mistake — do not hold it against the player.
      g.hintsUsed++;
      g.selected = h.index;
      _hintIndex = h.index;
      _autoCross();
    });
    _haptic(true);
    AudioService.instance.play(Sfx.hintUsed);
    if (!mounted) return;
    // Explain the TECHNIQUE. A hint that just fills a square teaches nothing
    // and leaves the player equally stuck next time.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(h.explanation, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 8),
      ));
    if (g.isSolved) _win();
    _save();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
          content: Text(m, style: const TextStyle(fontSize: 17)),
          duration: const Duration(seconds: 2)));
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _win() async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    AudioService.instance.play(Sfx.puzzleComplete);
    await widget.progress.clearSavedGame();

    final key = g.puzzle.difficulty.label;
    if (widget.dailyDate != null) {
      await widget.progress.markComplete(widget.dailyDate!,
          seconds: g.elapsedSeconds,
          difficultyKey: key,
          pictureName: g.puzzle.pictureName);
    } else {
      await widget.progress
          .recordPractice(g.elapsedSeconds, key, g.puzzle.pictureName);
    }
    if (!mounted) return;

    final streak = widget.progress.currentStreak;
    // A daily streak extending is the one moment worth a second chime.
    if (widget.dailyDate != null && streak > 1) {
      AudioService.instance.play(Sfx.streakUp);
    }
    final best = widget.progress.bestTimes[key];
    final isBest = best != null && g.elapsedSeconds <= best;
    final fs = widget.settings.fontScale;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Solved!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The picture's name is the payoff, revealed only now — showing it
            // up front would give the whole puzzle away.
            Text('It\'s a ${g.puzzle.pictureName.toLowerCase()}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24 * fs, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('Time ${_fmt(g.elapsedSeconds)}',
                style: TextStyle(fontSize: 19 * fs)),
            if (isBest)
              Text('Your best yet',
                  style: TextStyle(
                      fontSize: 17 * fs, fontWeight: FontWeight.w600)),
            if (widget.dailyDate != null && streak > 1)
              Text('$streak days in a row',
                  style: TextStyle(fontSize: 17 * fs)),
            const SizedBox(height: 8),
            Text('Hints ${g.hintsUsed}   ·   Mistakes ${g.mistakes}',
                style: TextStyle(fontSize: 15 * fs)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
    // Interstitial only AFTER the reward, never mid-puzzle.
    widget.ads.maybeShowInterstitial();
  }

  Future<bool> _confirmLeave() async {
    if (_finished || !g.canUndo) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this puzzle?'),
        content: const Text(
            'Your progress is saved. You can carry on from the main screen.',
            style: TextStyle(fontSize: 17)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final fs = s.fontScale;
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Capture the navigator BEFORE the awaits: the analyzer is right that
        // reading it afterwards is unsafe, and on a slow device this widget
        // really can be disposed while the dialog is open.
        final nav = Navigator.of(context);
        await _save();
        final leave = await _confirmLeave();
        if (!leave || !mounted) return;
        AudioService.instance.play(Sfx.navigateBack);
        nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Semantics(
                  label: 'Time so far ${_fmt(g.elapsedSeconds)}. '
                      'There is no time limit.',
                  child: Text(_fmt(g.elapsedSeconds),
                      style: TextStyle(
                          fontSize: 19 * fs,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${g.remaining} squares left',
                        style: TextStyle(fontSize: 16.5 * fs)),
                    Text(g.puzzle.difficulty.label,
                        style: TextStyle(
                            fontSize: 16.5 * fs,
                            color: scheme.onSurface.withValues(alpha: .72))),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) {
                          // Errors are signalled by colour AND motion AND a
                          // shape change, never by colour alone.
                          final dx = math.sin(_shake.value * math.pi * 4) *
                              6 *
                              (1 - _shake.value);
                          return Transform.translate(
                              offset: Offset(dx, 0), child: child);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: NonogramBoard(
                            game: g,
                            fontScale: fs,
                            highContrast: s.highContrast,
                            highlightLine: s.highlightLine,
                            showMistakes: s.showMistakes,
                            hintIndex: _hintIndex,
                            onCell: _tapCell,
                            onPaint: _paint,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _toolbar(fs, scheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(double fs, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Column(
        children: [
          // Tool picker. Two big targets, always visible, current one obvious
          // — a hidden mode is the classic way to lose someone in a nonogram.
          Row(
            children: [
              Expanded(
                child: _toolButton(
                  tool: Tool.fill,
                  icon: Icons.square_rounded,
                  label: 'Fill',
                  fs: fs,
                  scheme: scheme,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _toolButton(
                  tool: Tool.cross,
                  icon: Icons.close_rounded,
                  label: 'Cross out',
                  fs: fs,
                  scheme: scheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _action(
                    icon: Icons.undo,
                    label: 'Undo',
                    fs: fs,
                    onTap: g.canUndo ? _undo : null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                    icon: Icons.cleaning_services_outlined,
                    label: 'Fix',
                    fs: fs,
                    onTap: _clearMistakes),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                    icon: Icons.lightbulb_outline,
                    label: 'Hint',
                    fs: fs,
                    onTap: _hint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required Tool tool,
    required IconData icon,
    required String label,
    required double fs,
    required ColorScheme scheme,
  }) {
    final active = g.tool == tool;
    return Semantics(
      selected: active,
      button: true,
      child: SizedBox(
        height: 60,
        child: active
            ? FilledButton.icon(
                onPressed: () {
                  setState(() => g.tool = tool);
                  AudioService.instance.play(Sfx.buttonTap);
                },
                icon: Icon(icon, size: 26),
                label: Text(label, style: TextStyle(fontSize: 18 * fs)),
              )
            : OutlinedButton.icon(
                onPressed: () {
                  setState(() => g.tool = tool);
                  AudioService.instance.play(Sfx.buttonTap);
                  _haptic(true);
                },
                icon: Icon(icon,
                    size: 26,
                    color: tool == Tool.cross
                        ? AppTheme.crossColour(scheme)
                        : null),
                label: Text(label, style: TextStyle(fontSize: 18 * fs)),
              ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required double fs,
    required VoidCallback? onTap,
  }) =>
      SizedBox(
        height: 58,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              Text(label,
                  style: TextStyle(fontSize: 13.5 * fs),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );
}
