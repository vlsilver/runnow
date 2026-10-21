import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    FlutterSecureStorage? storage,
    RunNowElement initialElement = RunNowElement.water,
    RunNowAppearance initialAppearance = RunNowAppearance.light,
    RunNowDarkTone initialDarkTone = RunNowDarkTone.elemental,
    bool loadFromStorage = true,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    _element = initialElement;
    _appearance = initialAppearance;
    _darkTone = initialDarkTone;
    if (loadFromStorage) _load();
  }

  static const _elementKey = 'runnow_theme_element';
  static const _appearanceKey = 'runnow_theme_appearance';
  static const _darkToneKey = 'runnow_theme_dark_tone';
  static const _paletteVersionKey = 'runnow_theme_palette_version';
  static const _paletteVersion = '3';

  final FlutterSecureStorage _storage;
  late RunNowElement _element;
  late RunNowAppearance _appearance;
  late RunNowDarkTone _darkTone;

  RunNowElement get element => _element;
  RunNowAppearance get appearance => _appearance;
  RunNowDarkTone get darkTone => _darkTone;

  Future<void> setElement(RunNowElement element) async {
    if (_element == element) return;
    _element = element;
    notifyListeners();
    await _storage.write(key: _elementKey, value: element.name);
  }

  Future<void> setAppearance(RunNowAppearance appearance) async {
    if (_appearance == appearance) return;
    _appearance = appearance;
    notifyListeners();
    await _storage.write(key: _appearanceKey, value: appearance.name);
  }

  Future<void> setDarkTone(RunNowDarkTone darkTone) async {
    if (_darkTone == darkTone) return;
    _darkTone = darkTone;
    notifyListeners();
    await Future.wait([
      _storage.write(key: _darkToneKey, value: darkTone.name),
      _storage.write(key: _paletteVersionKey, value: _paletteVersion),
    ]);
  }

  Future<void> setSelection({
    required RunNowElement element,
    required RunNowAppearance appearance,
    required RunNowDarkTone darkTone,
  }) async {
    if (_element == element &&
        _appearance == appearance &&
        _darkTone == darkTone) {
      return;
    }
    _element = element;
    _appearance = appearance;
    _darkTone = darkTone;
    notifyListeners();
    await Future.wait([
      _storage.write(key: _elementKey, value: element.name),
      _storage.write(key: _appearanceKey, value: appearance.name),
      _storage.write(key: _darkToneKey, value: darkTone.name),
      _storage.write(key: _paletteVersionKey, value: _paletteVersion),
    ]);
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: _elementKey),
      _storage.read(key: _appearanceKey),
      _storage.read(key: _darkToneKey),
      _storage.read(key: _paletteVersionKey),
    ]);
    final loadedElement = switch (values[0]) {
      'metal' => RunNowElement.metal,
      'wood' => RunNowElement.wood,
      'fire' => RunNowElement.fire,
      'earth' => RunNowElement.earth,
      _ => RunNowElement.water,
    };
    // Mặc định Sáng (theo mockup): chỉ giữ Tối khi người dùng đã chọn rõ ràng.
    final loadedAppearance = values[1] == 'dark'
        ? RunNowAppearance.dark
        : RunNowAppearance.light;
    // Palette v3 follows the design source exactly: dark surfaces are neutral.
    final loadedDarkTone = RunNowDarkTone.elemental;
    if (_element == loadedElement &&
        _appearance == loadedAppearance &&
        _darkTone == loadedDarkTone) {
      return;
    }
    _element = loadedElement;
    _appearance = loadedAppearance;
    _darkTone = loadedDarkTone;
    notifyListeners();
  }
}
