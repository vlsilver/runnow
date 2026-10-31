import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/map_tiles.dart';

void main() {
  const osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  const cartoLight =
      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png?key=abc';
  const cartoDark =
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png?key=abc';

  test('no Remote Config: OpenStreetMap, inverted for dark mode', () {
    expect(resolveMapTiles(darkMode: false), (template: osm, invert: false));
    expect(resolveMapTiles(darkMode: true), (template: osm, invert: true));
  });

  test('a provider with its own dark style is used as is', () {
    expect(
      resolveMapTiles(light: cartoLight, dark: cartoDark, darkMode: true),
      (template: cartoDark, invert: false),
    );
    expect(
      resolveMapTiles(light: cartoLight, dark: cartoDark, darkMode: false),
      (template: cartoLight, invert: false),
    );
  });

  test('the same URL for both modes means the dark look is inverted', () {
    expect(resolveMapTiles(light: osm, dark: osm, darkMode: true), (
      template: osm,
      invert: true,
    ));
  });

  test('broken Remote Config values fall back to OpenStreetMap', () {
    for (final remote in [
      '',
      '   ',
      'basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}.png',
    ]) {
      expect(resolveMapTiles(light: remote, dark: remote, darkMode: true), (
        template: osm,
        invert: true,
      ), reason: remote);
    }
  });

  test('CARTO is credited only while its tiles are shown', () {
    expect(
      [for (final c in mapTileCredits(osm)) c.label],
      ['OpenStreetMap contributors'],
    );
    expect(
      [for (final c in mapTileCredits(cartoDark)) c.label],
      ['OpenStreetMap contributors', 'CARTO'],
    );
  });

  testWidgets('retina only asks the server when the URL has {r}', (
    tester,
  ) async {
    // Không có {r} mà bật retina thì flutter_map tải gấp 4 tile ở zoom cao
    // hơn để giả lập: tốn lượt gọi OSM và chữ trên bản đồ bị nhỏ.
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    late TileLayer light;
    late TileLayer dark;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          light = mapTileLayer(context, dark: false);
          dark = mapTileLayer(context, dark: true);
          return const SizedBox();
        },
      ),
    );
    expect(light.urlTemplate, osm);
    expect(light.resolvedRetinaMode, RetinaMode.disabled);
    expect(light.tileBuilder, isNull);
    expect(dark.tileBuilder, isNotNull);
  });
}
