import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/map_tiles.dart';

void main() {
  const carto = 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
  const keyed = '$carto?key=abc';

  test('Remote Config template wins when it is a usable tile URL', () {
    expect(resolveMapTileTemplate(keyed, dark: true), keyed);
  });

  test('missing or broken Remote Config value keeps the built-in tiles', () {
    for (final remote in [
      null,
      '',
      '   ',
      'basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
      'https://basemaps.cartocdn.com/dark_all/{z}/{x}.png',
    ]) {
      expect(resolveMapTileTemplate(remote, dark: true), carto, reason: remote);
    }
    expect(
      resolveMapTileTemplate(null, dark: false),
      'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    );
  });
}
