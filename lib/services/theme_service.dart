import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  static const _keyMode = 'theme_mode';
  static const _keyColor = 'theme_color';

  ThemeMode _mode = ThemeMode.system;
  Color _seed = const Color(0xFF1B6B3A);

  ThemeMode get mode => _mode;
  Color get seed => _seed;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final m = sp.getString(_keyMode) ?? 'system';
    _mode = {'light': ThemeMode.light, 'dark': ThemeMode.dark}[m] ??
        ThemeMode.system;
    final c = sp.getInt(_keyColor);
    if (c != null) _seed = Color(c);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _keyMode,
        m == ThemeMode.light
            ? 'light'
            : m == ThemeMode.dark
                ? 'dark'
                : 'system');
    notifyListeners();
  }

  Future<void> setSeed(Color c) async {
    _seed = c;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyColor, c.value);
    notifyListeners();
  }

  ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      );

  ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      );

  static const List<Color> presetColors = [
    Color(0xFF1B6B3A),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFFEF6C00),
    Color(0xFF00838F),
    Color(0xFF37474F),
    Color(0xFF4E342E),
    Color(0xFF2E7D32),
    Color(0xFF4527A0),
  ];
}
