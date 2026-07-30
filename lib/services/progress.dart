/// Streaks, best times, solved-picture album, and the mid-puzzle save slot.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Progress extends ChangeNotifier {
  static const _kDates = 'completed_dates';
  static const _kBest = 'best_times';
  static const _kTotal = 'total_puzzles';
  static const _kSeconds = 'total_seconds';
  static const _kSave = 'saved_game';
  static const _kAlbum = 'solved_pictures';

  SharedPreferences? _p;
  final Set<String> _dates = {};
  final Map<String, int> _best = {};
  /// Names of pictures the player has completed. The album is the long-term
  /// reason to come back — a streak counter rewards not missing a day, an
  /// album rewards having played at all, which is kinder.
  final Set<String> _album = {};
  int _total = 0;
  int _seconds = 0;

  Map<String, int> get bestTimes => Map.unmodifiable(_best);
  Set<String> get album => Set.unmodifiable(_album);
  int get totalPuzzles => _total;
  int get totalSeconds => _seconds;

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    _dates
      ..clear()
      ..addAll(_p?.getStringList(_kDates) ?? const []);
    _album
      ..clear()
      ..addAll(_p?.getStringList(_kAlbum) ?? const []);
    _total = _p?.getInt(_kTotal) ?? 0;
    _seconds = _p?.getInt(_kSeconds) ?? 0;
    _best.clear();
    final raw = _p?.getString(_kBest);
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>)
            .forEach((k, v) => _best[k] = v as int);
      } catch (_) {
        // Corrupt stats are not worth crashing over; start them fresh.
      }
    }
    notifyListeners();
  }

  bool isComplete(DateTime d) => _dates.contains(key(d));

  /// Consecutive days up to and including today. A day missed resets it —
  /// but nothing else is lost, and the album keeps every picture.
  int get currentStreak {
    var n = 0;
    var d = DateTime.now();
    if (!isComplete(d)) {
      d = d.subtract(const Duration(days: 1));
      if (!isComplete(d)) return 0;
    }
    while (isComplete(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get bestStreak {
    if (_dates.isEmpty) return 0;
    final sorted = _dates.toList()..sort();
    var best = 1, run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final prev = DateTime.parse(sorted[i - 1]);
      final cur = DateTime.parse(sorted[i]);
      run = cur.difference(prev).inDays == 1 ? run + 1 : 1;
      if (run > best) best = run;
    }
    return best;
  }

  Future<void> markComplete(DateTime d,
      {required int seconds,
      required String difficultyKey,
      required String pictureName}) async {
    _dates.add(key(d));
    _album.add(pictureName);
    _total++;
    _seconds += seconds;
    final b = _best[difficultyKey];
    if (b == null || seconds < b) _best[difficultyKey] = seconds;
    await _flush();
  }

  Future<void> recordPractice(
      int seconds, String difficultyKey, String pictureName) async {
    _total++;
    _seconds += seconds;
    _album.add(pictureName);
    final b = _best[difficultyKey];
    if (b == null || seconds < b) _best[difficultyKey] = seconds;
    await _flush();
  }

  Future<void> _flush() async {
    await _p?.setStringList(_kDates, _dates.toList()..sort());
    await _p?.setStringList(_kAlbum, _album.toList()..sort());
    await _p?.setInt(_kTotal, _total);
    await _p?.setInt(_kSeconds, _seconds);
    await _p?.setString(_kBest, jsonEncode(_best));
    notifyListeners();
  }

  // ------------------------------------------------------------- save slot

  Future<void> saveGame(String encoded) async {
    await _p?.setString(_kSave, encoded);
  }

  String? loadGame() => _p?.getString(_kSave);

  Future<void> clearSavedGame() async {
    await _p?.remove(_kSave);
    notifyListeners();
  }
}
