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
    expect(palette.background, RunNowThemeTokens.darkSlate[0]);
    expect(palette.glassStart, RunNowThemeTokens.darkSlate[1]);
    expect(palette.border, RunNowThemeTokens.darkSlate[2]);
    expect(palette.foreground, RunNowThemeTokens.darkSlate[3]);
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

  test('main colors match Ngu Hanh Palette.html', () {
    expect(RunNowElement.wood.ramp[2], const Color(0xff2e8c45));
    expect(RunNowElement.fire.ramp[2], const Color(0xffb83a24));
    expect(RunNowElement.earth.ramp[2], const Color(0xffb5811f));
    expect(RunNowElement.metal.ramp[2], const Color(0xffa6883f));
    expect(RunNowElement.water.ramp[2], const Color(0xff2c7c95));
  });

  test('secondary color is the element that generates the primary element', () {
    for (final element in RunNowElement.values) {
      final palette = RunNowPalette.forSelection(element);
      expect(palette.secondary, element.supporting.ramp[2]);
      expect(palette.tertiary, element.supporting.ramp[1]);
    }
  });

  test('all selectable dark tones map to their design material', () {
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
    expect(backgrounds, hasLength(RunNowDarkTone.values.length));
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
        'runnow_theme_palette_version': '2',
      });
      final controller = ThemeController();

      await pumpEventQueue();

      expect(controller.element, RunNowElement.wood);
      expect(controller.appearance, RunNowAppearance.light);
      expect(controller.darkTone, RunNowDarkTone.cool);
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
