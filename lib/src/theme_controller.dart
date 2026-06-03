import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    FlutterSecureStorage? storage,
    ThemeMode initialMode = ThemeMode.dark,
    bool loadFromStorage = true,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    _mode = initialMode;
    if (loadFromStorage) _load();
  }

  static const _storageKey = 'runnow_theme_mode';

  final FlutterSecureStorage _storage;
  late ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    await _storage.write(key: _storageKey, value: mode.name);
  }

  Future<void> _load() async {
    final value = await _storage.read(key: _storageKey);
    final loaded = switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    if (_mode == loaded) return;
    _mode = loaded;
    notifyListeners();
  }
}
