// Sinh bộ glyph SDF (định dạng glyph PBF của MapLibre) từ font của app, để màn
// replay 3D vẽ được tên đường. MapLibre native không dùng được font của
// Flutter, nó tải từng dải 256 ký tự theo `{fontstack}/{range}.pbf`.
//
// Chạy: flutter test tool/build_map_glyphs.dart
// Kết quả nằm ở web/map-glyphs/, đi theo bản web lên Firebase Hosting.
//
// Sinh đủ 256 dải của BMP, dải font không có ký tự nào thì file chỉ có phần
// đầu: MapLibre gặp 404 ở một dải là bỏ luôn chữ của cả tile đó.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fontFile = 'assets/fonts/barlow_condensed/BarlowCondensed-SemiBold.ttf';
const _stack = 'BarlowCondensed-SemiBold';
const _outDir = 'web/map-glyphs';

const _family = 'GlyphSource';

/// Cỡ chữ, vùng đệm và cách mã hoá khoảng cách theo quy ước của glyph PBF.
const _size = 24.0;
const _buffer = 3;
const _radius = 8.0;
const _cutoff = 0.25;

/// Vẽ to gấp [_scale] lần rồi đo khoảng cách trên ảnh to cho nét mịn.
const _scale = 4;
const _pad = 16;

void main() {
  testWidgets('sinh glyph PBF', (tester) async {
    final bytes = File(_fontFile).readAsBytesSync();
    final loader = FontLoader(_family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    final codepoints = _codepoints(ByteData.sublistView(bytes));

    final ranges = <int, List<_Glyph>>{};
    await tester.runAsync(() async {
      for (final cp in codepoints) {
        if (cp < 0x20 || cp > 0xFFFF) continue;
        (ranges[cp ~/ 256] ??= []).add(await _render(cp));
      }
    });

    final dir = Directory('$_outDir/$_stack');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    for (var r = 0; r < 256; r++) {
      final range = '${r * 256}-${r * 256 + 255}';
      File(
        '${dir.path}/$range.pbf',
      ).writeAsBytesSync(_encodeStack(range, ranges[r] ?? const []));
    }
    final total = ranges.values.fold(0, (sum, list) => sum + list.length);
    // ignore: avoid_print
    print('$total glyph, ${ranges.length} dải có ký tự -> ${dir.path}');
    expect(total, greaterThan(0));
  });
}

class _Glyph {
  const _Glyph({
    required this.id,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.advance,
    this.bitmap,
  });

  final int id;
  final int width;
  final int height;
  final int left;
  final int top;
  final int advance;
  final Uint8List? bitmap;
}

Future<_Glyph> _render(int cp) async {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(fontFamily: _family, fontSize: _size),
        )
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF)))
        ..addText(String.fromCharCode(cp));
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 1000));
  final advance = paragraph.maxIntrinsicWidth;
  final baseline = paragraph.alphabeticBaseline;
  final ascent = paragraph.computeLineMetrics().first.ascent;

  final w = (advance.ceil() + 2 * _pad) * _scale;
  final h = (paragraph.height.ceil() + 2 * _pad) * _scale;
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..scale(_scale.toDouble())
    ..drawParagraph(paragraph, Offset(_pad.toDouble(), _pad.toDouble()));
  final image = await recorder.endRecording().toImage(w, h);
  final rgba = (await image.toByteData())!;
  image.dispose();
  bool inside(int x, int y) =>
      x >= 0 &&
      y >= 0 &&
      x < w &&
      y < h &&
      rgba.getUint8((y * w + x) * 4 + 3) >= 128;

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!inside(x, y)) continue;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
  }
  if (maxX < 0) {
    return _Glyph(
      id: cp,
      width: 0,
      height: 0,
      left: 0,
      top: 0,
      advance: advance.round(),
    );
  }

  final x0 = minX ~/ _scale;
  final y0 = minY ~/ _scale;
  final width = (maxX + _scale) ~/ _scale - x0;
  final height = (maxY + _scale) ~/ _scale - y0;
  final cols = width + 2 * _buffer;
  final rows = height + 2 * _buffer;
  final reach = (_radius * _scale).ceil();
  final bitmap = Uint8List(cols * rows);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      // Tâm ô (i, j) của bitmap, tính theo pixel của ảnh to.
      final cx = ((x0 - _buffer + i) * _scale + _scale / 2).floor();
      final cy = ((y0 - _buffer + j) * _scale + _scale / 2).floor();
      final here = inside(cx, cy);
      var best = reach * reach + 1;
      for (var dy = -reach; dy <= reach; dy++) {
        for (var dx = -reach; dx <= reach; dx++) {
          final d2 = dx * dx + dy * dy;
          if (d2 >= best) continue;
          if (inside(cx + dx, cy + dy) != here) best = d2;
        }
      }
      final distance = math.sqrt(best) / _scale;
      final signed = here ? -distance : distance;
      bitmap[j * cols + i] = (255 - 255 * (signed / _radius + _cutoff))
          .round()
          .clamp(0, 255);
    }
  }
  return _Glyph(
    id: cp,
    width: width,
    height: height,
    left: x0 - _pad,
    top: (_pad + baseline).round() - y0 - ascent.round(),
    advance: advance.round(),
    bitmap: bitmap,
  );
}

/// Các ký tự font có hình, đọc từ bảng `cmap` (format 4 và 12).
List<int> _codepoints(ByteData font) {
  final tables = font.getUint16(4);
  int? cmap;
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes([
      for (var k = 0; k < 4; k++) font.getUint8(record + k),
    ]);
    if (tag == 'cmap') cmap = font.getUint32(record + 8);
  }
  if (cmap == null) throw StateError('Font không có bảng cmap');

  final found = <int>{};
  final subtables = font.getUint16(cmap + 2);
  for (var i = 0; i < subtables; i++) {
    final table = cmap + font.getUint32(cmap + 4 + i * 8 + 4);
    final format = font.getUint16(table);
    if (format == 4) {
      final segments = font.getUint16(table + 6) ~/ 2;
      final ends = table + 14;
      final starts = ends + segments * 2 + 2;
      final deltas = starts + segments * 2;
      final offsets = deltas + segments * 2;
      for (var s = 0; s < segments; s++) {
        final start = font.getUint16(starts + s * 2);
        final end = font.getUint16(ends + s * 2);
        final delta = font.getUint16(deltas + s * 2);
        final offset = font.getUint16(offsets + s * 2);
        for (var cp = start; cp <= end && cp != 0xFFFF; cp++) {
          final glyph = offset == 0
              ? (cp + delta) & 0xFFFF
              : font.getUint16(offsets + s * 2 + offset + (cp - start) * 2);
          if (glyph != 0) found.add(cp);
        }
      }
    } else if (format == 12) {
      final groups = font.getUint32(table + 12);
      for (var g = 0; g < groups; g++) {
        final group = table + 16 + g * 12;
        final start = font.getUint32(group);
        final end = font.getUint32(group + 4);
        for (var cp = start; cp <= end; cp++) {
          found.add(cp);
        }
      }
    }
  }
  if (found.isEmpty) throw StateError('Không đọc được ký tự nào từ cmap');
  return found.toList()..sort();
}

void _varint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addByte(v);
}

void _field(BytesBuilder out, int number, int value) {
  _varint(out, number << 3);
  _varint(out, value);
}

void _bytes(BytesBuilder out, int number, List<int> value) {
  _varint(out, (number << 3) | 2);
  _varint(out, value.length);
  out.add(value);
}

int _zigzag(int value) => value >= 0 ? value * 2 : -value * 2 - 1;

/// `glyphs { stacks = 1 { name = 1; range = 2; glyphs = 3 {...} } }`.
Uint8List _encodeStack(String range, List<_Glyph> glyphs) {
  final stack = BytesBuilder();
  _bytes(stack, 1, _stack.codeUnits);
  _bytes(stack, 2, range.codeUnits);
  for (final glyph in glyphs) {
    final g = BytesBuilder();
    _field(g, 1, glyph.id);
    if (glyph.bitmap case final bitmap?) _bytes(g, 2, bitmap);
    _field(g, 3, glyph.width);
    _field(g, 4, glyph.height);
    _field(g, 5, _zigzag(glyph.left));
    _field(g, 6, _zigzag(glyph.top));
    _field(g, 7, glyph.advance);
    _bytes(stack, 3, g.takeBytes());
  }
  final out = BytesBuilder();
  _bytes(out, 1, stack.takeBytes());
  return out.takeBytes();
}
