import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/widgets/map_vector.dart';

Map<String, dynamic> _style({required String glyphUrl}) =>
    jsonDecode(
          replayMapStyle(
            dark: false,
            route: const [
              [106.70, 10.77],
              [106.71, 10.78],
            ],
            line: const Color(0xFFE23B2E),
            outline: const Color(0xFF151515),
            glyphUrl: glyphUrl,
          ),
        )
        as Map<String, dynamic>;

List<Map<String, dynamic>> _symbols(Map<String, dynamic> style) => [
  for (final layer in style['layers'] as List)
    if (layer['type'] == 'symbol') layer as Map<String, dynamic>,
];

void main() {
  group('vectorMapCovers', () {
    // Toạ độ tra tay: Hà Nội, Côn Đảo, Phú Quốc trong Việt Nam; Athens ngoài.
    test('tuyến nằm trọn trong Việt Nam thì có tile vector', () {
      expect(
        vectorMapCovers(const [
          LatLng(21.03, 105.85),
          LatLng(8.68, 106.60),
          LatLng(10.22, 103.96),
        ]),
        isTrue,
      );
    });

    test('tuyến ở nước ngoài thì không có', () {
      expect(vectorMapCovers(const [LatLng(37.97, 23.74)]), isFalse);
    });

    test('một điểm ra ngoài Việt Nam là cả tuyến không được phủ', () {
      // Hà Nội rồi Bangkok.
      expect(
        vectorMapCovers(const [LatLng(21.03, 105.85), LatLng(13.75, 100.50)]),
        isFalse,
      );
    });

    test('chưa có điểm nào thì coi như trong vùng phủ', () {
      expect(vectorMapCovers(const []), isTrue);
    });
  });

  group('replayMapStyle', () {
    test('chưa có nguồn glyph thì không có lớp chữ nào', () {
      final style = _style(glyphUrl: '');

      expect(style.containsKey('glyphs'), isFalse);
      expect(_symbols(style), isEmpty);
    });

    test('có nguồn glyph thì chỉ vẽ tên đường, bằng bộ glyph đã sinh', () {
      const url = 'https://example.test/map-glyphs/{fontstack}/{range}.pbf';
      final style = _style(glyphUrl: url);
      final symbols = _symbols(style);

      expect(style['glyphs'], url);
      // Chỉ tên đường: không có tên phường, khu phố, thành phố.
      expect(symbols.map((layer) => layer['id']), ['roads-label']);
      for (final layer in symbols) {
        final fonts = (layer['layout'] as Map)['text-font'] as List;
        expect(fonts, ['BarlowCondensed-SemiBold'], reason: '${layer['id']}');
        // Dải có chữ tiếng Việt dấu kép (ế, ộ, ữ...).
        final glyphs = File('web/map-glyphs/${fonts.single}/7680-7935.pbf');
        expect(glyphs.lengthSync(), greaterThan(10000));
      }
    });
  });
}
