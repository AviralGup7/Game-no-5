/// Persisted preferences. The app OPENS large; users can shrink it if they
/// want. Competing puzzle apps ship small type and expect people to hunt for a
/// settings screen — we invert that.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends ChangeNotifier {
  static const _kFont = 'font_scale';
  static const _kContrast = 'high_contrast';
  static const _kDark = 'dark_mode';
  static const _kHaptics = 'haptics';
  static const _kSound = 'sound';
  static const _kMusic = 'music';
  static const _kAdFree = 'ad_free';
  static const _kMistakes = 'show_mistakes';
  static const _kHighlight = 'highlight_line';
  static const _kAutoCross = 'auto_cross';
  static const _kSeenTutorial = 'seen_tutorial';

  SharedPreferences? _p;

  double _fontScale = 1.15;
  bool _highContrast = false;
  bool _darkMode = false;
  bool _haptics = true;
  /// Quiet, mono confirmation sounds. ON by default.
  bool _sound = true;
  /// Background music is OPT-IN. Audio that starts unasked is an uninstall
  /// trigger for this audience.
  bool _music = false;
  bool _adFree = false;
  /// Flag a wrong mark immediately. ON by default: in a nonogram one bad
  /// square poisons every deduction made after it, and finding that out 40
  /// moves later means starting over.
  bool _showMistakes = true;
  /// Shade the row and column under your finger — the main scanning aid on a
  /// grid this size.
  bool _highlightLine = true;
  /// When a line's clues are satisfied, cross out the rest of it for you.
  /// This is the tedious bookkeeping part, and doing it by hand is where
  /// people give up.
  bool _autoCross = true;
  bool _seenTutorial = false;

  double get fontScale => _fontScale;
  bool get highContrast => _highContrast;
  bool get darkMode => _darkMode;
  bool get haptics => _haptics;
  bool get sound => _sound;
  bool get music => _music;
  bool get adFree => _adFree;
  bool get showMistakes => _showMistakes;
  bool get highlightLine => _highlightLine;
  bool get autoCross => _autoCross;
  bool get seenTutorial => _seenTutorial;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    _fontScale = _p?.getDouble(_kFont) ?? 1.15;
    _highContrast = _p?.getBool(_kContrast) ?? false;
    _darkMode = _p?.getBool(_kDark) ?? false;
    _haptics = _p?.getBool(_kHaptics) ?? true;
    _sound = _p?.getBool(_kSound) ?? true;
    _music = _p?.getBool(_kMusic) ?? false;
    _adFree = _p?.getBool(_kAdFree) ?? false;
    _showMistakes = _p?.getBool(_kMistakes) ?? true;
    _highlightLine = _p?.getBool(_kHighlight) ?? true;
    _autoCross = _p?.getBool(_kAutoCross) ?? true;
    _seenTutorial = _p?.getBool(_kSeenTutorial) ?? false;
    notifyListeners();
  }

  Future<void> _set(String k, Object v) async {
    if (v is bool) await _p?.setBool(k, v);
    if (v is double) await _p?.setDouble(k, v);
    notifyListeners();
  }

  Future<void> setFontScale(double v) async {
    _fontScale = v.clamp(0.85, 1.6);
    await _set(_kFont, _fontScale);
  }

  Future<void> setHighContrast(bool v) async { _highContrast = v; await _set(_kContrast, v); }
  Future<void> setDarkMode(bool v) async { _darkMode = v; await _set(_kDark, v); }
  Future<void> setHaptics(bool v) async { _haptics = v; await _set(_kHaptics, v); }
  Future<void> setSound(bool v) async { _sound = v; await _set(_kSound, v); }
  Future<void> setMusic(bool v) async { _music = v; await _set(_kMusic, v); }
  Future<void> setAdFree(bool v) async { _adFree = v; await _set(_kAdFree, v); }
  Future<void> setShowMistakes(bool v) async { _showMistakes = v; await _set(_kMistakes, v); }
  Future<void> setHighlightLine(bool v) async { _highlightLine = v; await _set(_kHighlight, v); }
  Future<void> setAutoCross(bool v) async { _autoCross = v; await _set(_kAutoCross, v); }
  Future<void> markTutorialSeen() async { _seenTutorial = true; await _set(_kSeenTutorial, true); }
}
