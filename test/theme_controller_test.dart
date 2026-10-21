import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dark theme uses the selected element and neutral dark material', () {
    final theme = buildRunNowTheme(
      RunNowElement.fire,
      darkTone: RunNowDarkTone.slate,
    );
    final palette = theme.extension<RunNowPalette>()!;

    expect(theme.brightness, Brightness.dark);
    expect(palette.element, RunNowElement.fire);
    expect(palette.accent, RunNowThemeTokens.fireRamp[2]);
    expect(palette.background, RunNowThemeTokens.darkNeutral[0]);
    expect(palette.glassStart, RunNowThemeTokens.darkNeutral[1]);
    expect(palette.border, RunNowThemeTokens.darkNeutral[2]);
    expect(palette.foreground, RunNowThemeTokens.darkNeutral[3]);
  });

  test('light theme uses the selected element material from the design', () {
    for (final element in RunNowElement.values) {
      final palette = RunNowPalette.forSelection(
        element,
        appearance: RunNowAppearance.light,
      );
      final material = element.lightMaterial;

      expect(palette.appearance, RunNowAppearance.light);
      expect(palette.background, material[0]);
      expect(palette.glassStart, material[1]);
      expect(palette.border, material[2]);
      expect(palette.foreground, material[3]);
    }
  });

  test('five elements use the exact main colors from the design ramps', () {
    final palettes = [
      for (final element in RunNowElement.values)
        RunNowPalette.forSelection(element),
    ];

    expect(palettes.map((palette) => palette.accent).toSet(), hasLength(5));
    for (final palette in palettes) {
      expect(palette.accent, palette.element.ramp[2]);
      expect(palette.accentDeep, palette.element.ramp[3]);
    }
  });

  test('brand colors match Quy tac mau · Runow', () {
    expect(RunNowElement.wood.ramp[2], const Color(0xff8fd400));
    expect(RunNowElement.fire.ramp[2], const Color(0xffff5230));
    expect(RunNowElement.earth.ramp[2], const Color(0xffce7b2c));
    expect(RunNowElement.metal.ramp[2], const Color(0xffc9a53a));
    expect(RunNowElement.water.ramp[2], const Color(0xff0e96a8));
    // brand-strong (ramp[3]) — chữ/viền/icon trên nền sáng.
    expect(RunNowElement.fire.ramp[3], const Color(0xffe23b27));
  });

  test('a palette never mixes brand colors from another element', () {
    for (final element in RunNowElement.values) {
      final palette = RunNowPalette.forSelection(element);
      expect(palette.secondary, element.ramp[3]);
      expect(palette.tertiary, element.ramp[1]);
    }
  });

  test('light themes share the neutral 60 percent background', () {
    final backgrounds = {
      for (final element in RunNowElement.values)
        RunNowPalette.forSelection(
          element,
          appearance: RunNowAppearance.light,
        ).background,
    };

    expect(backgrounds, {RunNowThemeTokens.lightNeutral[0]});
  });

  test('component colors follow the 60 30 10 hierarchy', () {
    final theme = buildRunNowTheme(
      RunNowElement.fire,
      appearance: RunNowAppearance.light,
    );
    final palette = theme.extension<RunNowPalette>()!;
    final filledStyle = theme.filledButtonTheme.style!;

    expect(filledStyle.backgroundColor!.resolve({}), palette.ink);
    expect(filledStyle.foregroundColor!.resolve({}), palette.accent);
    expect(theme.floatingActionButtonTheme.backgroundColor, palette.accent);
    expect(theme.cardTheme.color, palette.glassStart);
  });

  test('all legacy dark tones resolve to the design neutral material', () {
    final backgrounds = <Color>{};
    for (final tone in RunNowDarkTone.values) {
      final palette = RunNowPalette.forSelection(
        RunNowElement.water,
        darkTone: tone,
      );
      backgrounds.add(palette.background);
      final material = tone.materialFor(RunNowElement.water);
      expect(palette.background, material[0]);
      expect(palette.glassStart, material[1]);
      expect(palette.border, material[2]);
      expect(palette.foreground, material[3]);
    }
    expect(backgrounds, hasLength(1));
  });

  test('light and dark ThemeData expose matching brightness', () {
    final light = buildRunNowTheme(
      RunNowElement.wood,
      appearance: RunNowAppearance.light,
    );
    final dark = buildRunNowTheme(
      RunNowElement.wood,
      appearance: RunNowAppearance.dark,
    );

    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme.brightness, Brightness.dark);
  });

  test('theme controller persists element appearance and dark tone', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final controller = ThemeController(
      storage: storage,
      loadFromStorage: false,
    );

    await controller.setSelection(
      element: RunNowElement.earth,
      appearance: RunNowAppearance.light,
      darkTone: RunNowDarkTone.warm,
    );

    expect(controller.element, RunNowElement.earth);
    expect(controller.appearance, RunNowAppearance.light);
    expect(controller.darkTone, RunNowDarkTone.warm);
    expect(
      await storage.read(key: 'runnow_theme_element'),
      RunNowElement.earth.name,
    );
    expect(
      await storage.read(key: 'runnow_theme_appearance'),
      RunNowAppearance.light.name,
    );
    expect(
      await storage.read(key: 'runnow_theme_dark_tone'),
      RunNowDarkTone.warm.name,
    );
  });

  test(
    'theme controller restores the complete selection after restart',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'runnow_theme_element': 'wood',
        'runnow_theme_appearance': 'light',
        'runnow_theme_dark_tone': 'cool',
        'runnow_theme_palette_version': '3',
      });
      final controller = ThemeController();

      await pumpEventQueue();

      expect(controller.element, RunNowElement.wood);
      expect(controller.appearance, RunNowAppearance.light);
      expect(controller.darkTone, RunNowDarkTone.elemental);
    },
  );

  test('legacy dark selection migrates from the foggy dim default', () async {
    FlutterSecureStorage.setMockInitialValues({
      'runnow_theme_element': 'fire',
      'runnow_theme_appearance': 'dark',
      'runnow_theme_dark_tone': 'dim',
    });
    final controller = ThemeController();

    await pumpEventQueue();

    expect(controller.element, RunNowElement.fire);
    expect(controller.appearance, RunNowAppearance.dark);
    expect(controller.darkTone, RunNowDarkTone.elemental);
  });
}
